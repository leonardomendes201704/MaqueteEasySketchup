module LeonardoLabs
  module PlanForgeBuilder
    class RoomTool
      TOLERANCE = 1.mm
      PROMPT = 'Clique para posicionar o canto inferior do comodo. Esc cancela.'.freeze

      def initialize(interior_width, interior_depth, settings = Settings.to_h)
        @interior_width = interior_width.to_f
        @interior_depth = interior_depth.to_f
        @settings = Settings.sanitize(settings)
      end

      def activate
        @mouse_ip = Sketchup::InputPoint.new
        @anchor_point = nil
        @preview_data = nil
        update_status(PROMPT)
      end

      def deactivate(view)
        clear_status
        view.invalidate if view
      end

      def resume(view)
        update_status(PROMPT)
        view.invalidate if view
      end

      def onCancel(_reason, view)
        @anchor_point = nil
        @preview_data = nil
        update_status(PROMPT)
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        @mouse_ip.pick(view, x, y)
        raw_point = if @mouse_ip.valid?
                      @mouse_ip.position
                    else
                      point_on_plane(view, x, y, 0.0)
                    end
        return unless raw_point

        @anchor_point = snap_point(raw_point)
        @preview_data = RoomBuilder.preview_rect_room(@anchor_point, @interior_width, @interior_depth, @settings)
        update_vcb
        view.invalidate
      end

      def onLButtonDown(_flags, _x, _y, view)
        return unless @anchor_point && @preview_data

        model = Sketchup.active_model
        model.start_operation('PlanForge Builder - Gerar comodo', true)
        RoomBuilder.build_rect_room(model, @anchor_point, @interior_width, @interior_depth, @settings)
        model.commit_operation
        update_status('Comodo gerado. Clique para posicionar outro.')
        view.invalidate
      rescue StandardError => error
        model.abort_operation rescue nil
        Diagnostics.error('room_tool.onLButtonDown', error)
        UI.messagebox("PlanForge Builder: erro ao gerar o comodo.\n\n#{error.message}")
        view.invalidate
      end

      def draw(view)
        draw_anchor(view)
        draw_preview(view)
      end

      def getExtents
        bounds = Geom::BoundingBox.new
        bounds.add(@anchor_point) if @anchor_point
        return bounds unless @preview_data

        bounds.add(@preview_data[:floor_outline]) unless @preview_data[:floor_outline].empty?
        @preview_data[:wall_previews].each do |preview|
          bounds.add(preview[:footprint])
          bounds.add(preview[:top])
        end
        bounds
      end

      private

      def draw_anchor(view)
        return unless @anchor_point

        color = Sketchup::Color.new(34, 87, 122)
        view.line_width = 2
        view.drawing_color = color
        view.draw_points([@anchor_point], 12, 3, color)
      end

      def draw_preview(view)
        return unless @preview_data

        floor_outline = @preview_data[:floor_outline]
        if floor_outline.length >= 4
          view.drawing_color = Sketchup::Color.new(43, 103, 119, 70)
          view.draw(GL_QUADS, floor_outline)
          view.line_width = 2
          view.drawing_color = Sketchup::Color.new(20, 55, 63)
          view.draw(GL_LINE_STRIP, floor_outline + [floor_outline.first])
        end

        @preview_data[:wall_previews].each do |preview|
          footprint = preview[:footprint]
          top = preview[:top]
          columns = []
          footprint.each_with_index do |point, index|
            columns << point
            columns << top[index]
          end

          view.drawing_color = Sketchup::Color.new(194, 116, 53, 70)
          view.draw(GL_QUADS, footprint)
          view.line_width = 2
          view.drawing_color = Sketchup::Color.new(128, 67, 24)
          view.draw(GL_LINE_STRIP, footprint + [footprint.first])
          view.draw(GL_LINE_STRIP, top + [top.first])
          view.draw(GL_LINES, columns)
        end

        draw_label(view)
      end

      def draw_label(view)
        label = "#{MetricUnits.format_meters(@interior_width)} x #{MetricUnits.format_meters(@interior_depth)}"
        text_point = @preview_data[:label_point].offset(Z_AXIS, @settings[:wall_height_cm].to_f.cm + 10.cm)
        view.draw_text(text_point, label)
      end

      def point_on_plane(view, x, y, z_value)
        ray = view.pickray(x, y)
        plane = [Geom::Point3d.new(0.0, 0.0, z_value), Z_AXIS]
        Geom.intersect_line_plane(ray, plane)
      end

      def snap_point(point)
        step = @settings[:snap_step_cm].to_f.cm
        return Geom::Point3d.new(point.x, point.y, point.z) if step <= 0.0

        Geom::Point3d.new(
          snap_scalar(point.x, step),
          snap_scalar(point.y, step),
          point.z
        )
      end

      def snap_scalar(value, step)
        (value.to_f / step).round * step
      end

      def update_status(prompt)
        Sketchup.set_status_text(prompt, SB_PROMPT)
        Sketchup.set_status_text('Comodo', SB_VCB_LABEL)
        update_vcb
      end

      def update_vcb
        value = "#{MetricUnits.format_meters(@interior_width)} x #{MetricUnits.format_meters(@interior_depth)}"
        Sketchup.set_status_text(value, SB_VCB_VALUE)
      end

      def clear_status
        Sketchup.set_status_text('', SB_PROMPT)
        Sketchup.set_status_text('', SB_VCB_LABEL)
        Sketchup.set_status_text('', SB_VCB_VALUE)
      end
    end
  end
end
