module LeonardoLabs
  module PlanForgeBuilder
    class DoorTool
      PROMPT = 'Passe o mouse sobre uma parede do PlanForge Builder e clique para criar o corte da porta.'.freeze

      def activate
        @mouse_ip = Sketchup::InputPoint.new
        @preview = nil
        update_status(PROMPT)
      end

      def deactivate(view)
        clear_status
        @preview = nil
        view.invalidate if view
      end

      def resume(view)
        update_status(PROMPT)
        view.invalidate
      end

      def onCancel(_reason, view)
        @preview = nil
        update_status(PROMPT)
        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        update_preview(view, x, y)
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        update_preview(view, x, y)
        return unless @preview

        model = Sketchup.active_model
        model.start_operation('PlanForge Builder - Corte de porta', true)
        GeometryBuilder.cut_door_opening(@preview[:group], @preview)
        model.commit_operation
        update_status('Corte de porta criado. Passe o mouse sobre outra parede para continuar.')
        update_preview(view, x, y)
        view.invalidate
      rescue StandardError => error
        model.abort_operation rescue nil
        Diagnostics.error('door_tool.onLButtonDown', error)
        UI.messagebox("PlanForge Builder: erro ao criar o corte da porta.\n\n#{error.message}")
      end

      def draw(view)
        return unless @preview

        front = @preview[:world_face]
        back = @preview[:world_back]
        columns = []

        front.each_with_index do |point, index|
          columns << point
          columns << back[index]
        end

        view.drawing_color = Sketchup::Color.new(49, 140, 231, 70)
        view.draw(GL_QUADS, front)
        view.draw(GL_QUADS, back)

        view.line_width = 2
        view.drawing_color = Sketchup::Color.new(13, 71, 161)
        view.draw(GL_LINE_STRIP, front + [front.first])
        view.draw(GL_LINE_STRIP, back + [back.first])
        view.draw(GL_LINES, columns)
        draw_label(view)
      end

      def getExtents
        bounds = Geom::BoundingBox.new
        return bounds unless @preview

        bounds.add(@preview[:world_face])
        bounds.add(@preview[:world_back])
        bounds
      end

      private

      def update_preview(view, x, y)
        @mouse_ip.pick(view, x, y)
        @preview = nil
        unless @mouse_ip.valid?
          update_vcb
          return
        end

        group = picked_wall_group(view, x, y)
        unless group
          update_vcb
          return
        end

        @preview = GeometryBuilder.door_preview_data(group, @mouse_ip.position, Settings.to_h)
        update_vcb
      rescue StandardError => error
        Diagnostics.error('door_tool.update_preview', error)
        @preview = nil
        update_vcb
      end

      def picked_wall_group(view, x, y)
        pick_helper = view.pick_helper
        pick_helper.do_pick(x, y)

        (0...pick_helper.count).each do |index|
          path = pick_helper.path_at(index)
          next unless path

          path.to_a.reverse_each do |entity|
            return entity if GeometryBuilder.wall_group?(entity)
          end
        end

        nil
      end

      def draw_label(view)
        label = "#{Sketchup.format_length(@preview[:door_width])} x #{Sketchup.format_length(@preview[:door_height])}"
        text_point = @preview[:midpoint].offset(Z_AXIS, 10.cm)
        view.draw_text(text_point, label)
      end

      def update_status(prompt)
        Sketchup.set_status_text(prompt, SB_PROMPT)
        Sketchup.set_status_text('Porta', SB_VCB_LABEL)
        update_vcb
      end

      def update_vcb
        value = if @preview
                  "#{Sketchup.format_length(@preview[:door_width])} x #{Sketchup.format_length(@preview[:door_height])}"
                else
                  ''
                end
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
