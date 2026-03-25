module LeonardoLabs
  module PlanForgeBuilder
    class WallTool
      TOLERANCE = 1.mm
      PROMPT_IDLE = 'Clique para iniciar a primeira parede.'.freeze
      PROMPT_DRAWING = 'Clique para concluir a parede. Enter fecha o comodo e cria piso/rodape. Esc cancela o tracado.'.freeze

      def activate
        @mouse_ip = Sketchup::InputPoint.new
        reset_chain
        update_status(PROMPT_IDLE)
      end

      def deactivate(view)
        clear_status
        view.invalidate if view
      end

      def resume(view)
        update_status(drawing? ? PROMPT_DRAWING : PROMPT_IDLE)
        view.invalidate
      end

      def onCancel(_reason, view)
        if drawing?
          reset_chain
          update_status('Tracado cancelado. Clique para iniciar outra parede.')
        else
          update_status(PROMPT_IDLE)
        end

        view.invalidate
      end

      def onMouseMove(_flags, x, y, view)
        if drawing?
          @preview_end = resolve_endpoint(view, x, y)
          @preview_data = if @preview_end
                            GeometryBuilder.preview_data(
                              @last_point,
                              @preview_end,
                              Settings.to_h,
                              preview_previous_point,
                              preview_next_point
                            )
                          end
          update_direction_cache
        else
          @mouse_ip.pick(view, x, y)
          raw_point = if @mouse_ip.valid?
                        @mouse_ip.position
                      else
                        point_on_plane(view, x, y, 0.0)
                      end
          @hover_point = raw_point ? snap_point(raw_point, raw_point.z) : nil
        end

        update_vcb
        view.invalidate
      end

      def onLButtonDown(_flags, x, y, view)
        if drawing?
          finalize_segment(resolve_endpoint(view, x, y))
        else
          point = initial_point(view, x, y)
          return unless point

          begin_chain(point)
        end

        view.invalidate
      rescue StandardError => error
        Diagnostics.error('wall_tool.onLButtonDown', error)
        reset_chain
        UI.messagebox("PlanForge Builder: erro ao criar parede.\n\n#{error.message}")
        view.invalidate
      end

      def onReturn(view)
        return unless drawing?
        return unless @chain_points.length >= 2

        finalize_segment(@chain_start_point)
        view.invalidate
      end

      def onUserText(text, view)
        return unless drawing?

        length = text.to_l
        raise ArgumentError, 'Comprimento invalido.' if length <= TOLERANCE

        direction = current_direction
        raise ArgumentError, 'Mova o mouse para definir a direcao antes de digitar o comprimento.' unless direction

        endpoint = Geom::Point3d.new(
          @last_point.x + (direction.x * length),
          @last_point.y + (direction.y * length),
          @last_point.z
        )
        endpoint = snap_point(endpoint, @last_point.z)
        endpoint = @chain_start_point if should_snap_to_chain_start?(endpoint)
        finalize_segment(endpoint)
        view.invalidate
      rescue StandardError => error
        Diagnostics.error('wall_tool.onUserText', error)
        UI.beep
        view.tooltip = error.message
      end

      def draw(view)
        draw_hover_point(view) unless drawing?
        draw_existing_path(view)
        draw_preview(view)
      end

      def getExtents
        bounds = Geom::BoundingBox.new
        @chain_points.each { |point| bounds.add(point) } if @chain_points
        bounds.add(@hover_point) if @hover_point

        if @preview_data
          bounds.add(@preview_data[:footprint])
          bounds.add(@preview_data[:top])
        end

        bounds
      end

      private

      def begin_chain(point)
        @chain_start_point = point
        @last_point = point
        @chain_points = [point]
        @wall_records = []
        @preview_end = nil
        @preview_data = nil
        @hover_point = nil
        update_status(PROMPT_DRAWING)
      end

      def finalize_segment(endpoint)
        return unless endpoint
        return if @last_point.distance(endpoint) <= TOLERANCE

        settings = Settings.to_h
        model = Sketchup.active_model
        closed_room = closes_room?(endpoint)
        contour = @chain_points + [endpoint]
        model.start_operation('PlanForge Builder - Criar parede', true)
        @wall_records << {
          :group => GeometryBuilder.build_wall(model, @last_point, endpoint, settings),
          :settings => Settings.sanitize(settings)
        }
        refresh_chain_walls(contour, closed_room)
        room_token = nil
        if closed_room
          room_token = GeometryBuilder.assign_room_metadata(@wall_records.map { |record| record[:group] }, contour, settings)
          @wall_records = RoomReconciler.reconcile_room(model, room_token, settings)[:walls].map do |group|
            { :group => group, :settings => GeometryBuilder.entity_settings(group) }
          end
        end
        if closed_room && should_create_floor?(contour, settings)
          floor_group = GeometryBuilder.build_floor(model, contour, settings)
          GeometryBuilder.tag_room_entity(floor_group, contour, settings, room_token)
        end
        if closed_room && should_create_baseboards?(contour, settings)
          BaseboardBuilder.build_for_room(
            model,
            contour,
            @wall_records.map { |record| record[:group] },
            settings,
            room_token,
            true
          )
        end
        model.commit_operation

        @chain_points << endpoint

        if closed_room
          reset_chain
          update_status('Comodo fechado. Clique para iniciar outro tracado.')
        else
          @last_point = endpoint
          @preview_end = nil
          @preview_data = nil
          update_status(PROMPT_DRAWING)
        end
      rescue StandardError => error
        model.abort_operation rescue nil
        raise error
      end

      def drawing?
        !@last_point.nil?
      end

      def reset_chain
        @chain_start_point = nil
        @last_point = nil
        @chain_points = []
        @wall_records = []
        @preview_end = nil
        @preview_data = nil
        @hover_point = nil
        @last_direction = nil
      end

      def initial_point(view, x, y)
        @mouse_ip.pick(view, x, y)
        raw_point = if @mouse_ip.valid?
                      @mouse_ip.position
                    else
                      point_on_plane(view, x, y, 0.0)
                    end
        return nil unless raw_point

        snap_point(raw_point, raw_point.z)
      end

      def resolve_endpoint(view, x, y)
        raw_point = point_on_plane(view, x, y, @last_point.z)
        return nil unless raw_point

        constrained = apply_axis_lock(@last_point, raw_point)
        endpoint = snap_point(constrained, @last_point.z)
        endpoint = @chain_start_point if should_snap_to_chain_start?(endpoint)
        return nil if @last_point.distance(endpoint) <= TOLERANCE

        endpoint
      end

      def point_on_plane(view, x, y, z_value)
        ray = view.pickray(x, y)
        plane = [Geom::Point3d.new(0.0, 0.0, z_value), Z_AXIS]
        Geom.intersect_line_plane(ray, plane)
      end

      def apply_axis_lock(start_point, point)
        return Geom::Point3d.new(point.x, point.y, start_point.z) unless Settings.current[:ortho_mode]

        delta = point - start_point
        if delta.x.abs >= delta.y.abs
          Geom::Point3d.new(point.x, start_point.y, start_point.z)
        else
          Geom::Point3d.new(start_point.x, point.y, start_point.z)
        end
      end

      def snap_point(point, z_value)
        step = Settings.length(:snap_step_cm).to_f
        return Geom::Point3d.new(point.x, point.y, z_value) if step <= 0.0

        Geom::Point3d.new(
          snap_scalar(point.x, step),
          snap_scalar(point.y, step),
          z_value
        )
      end

      def snap_scalar(value, step)
        (value.to_f / step).round * step
      end

      def should_snap_to_chain_start?(endpoint)
        return false unless @chain_start_point
        return false unless @chain_points.length >= 2

        threshold = [Settings.length(:snap_step_cm).to_f / 2.0, 1.cm.to_f].max
        endpoint.distance(@chain_start_point).to_f <= threshold
      end

      def closes_room?(endpoint)
        @chain_start_point && @chain_points.length >= 2 && endpoint.distance(@chain_start_point) <= TOLERANCE
      end

      def should_create_floor?(contour, settings)
        settings[:create_floor_on_close] && unique_room_points(contour).length >= 3
      end

      def should_create_baseboards?(contour, settings)
        settings[:create_baseboard_on_close] && unique_room_points(contour).length >= 3
      end

      def unique_room_points(points)
        unique = []
        Array(points).each do |point|
          next if unique.any? { |existing| existing.distance(point) <= TOLERANCE }

          unique << point
        end
        unique
      end

      def refresh_chain_walls(path_points, closed_room)
        segment_count = [@wall_records.length, path_points.length - 1].min
        return if segment_count <= 0

        segment_count.times do |index|
          prev_point, next_point = adjacent_points_for_segment(path_points, index, closed_room)
          record = @wall_records[index]
          GeometryBuilder.rebuild_wall(
            record[:group],
            path_points[index],
            path_points[index + 1],
            record[:settings],
            prev_point,
            next_point
          )
        end
      end

      def adjacent_points_for_segment(path_points, segment_index, closed_room)
        prev_point = segment_index.positive? ? path_points[segment_index - 1] : nil
        next_point = (segment_index + 2) < path_points.length ? path_points[segment_index + 2] : nil

        if closed_room
          prev_point = path_points[-2] if segment_index.zero?
          next_point = path_points[1] if segment_index == (path_points.length - 2)
        end

        [prev_point, next_point]
      end

      def preview_previous_point
        return nil unless @chain_points.length >= 2

        @chain_points[-2]
      end

      def preview_next_point
        return nil unless @preview_end
        return nil unless closes_room?(@preview_end)

        @chain_points[1]
      end

      def update_direction_cache
        return unless @preview_data

        direction = @preview_data[:vector]
        return unless direction && direction.length > TOLERANCE

        direction.normalize!
        @last_direction = direction
      end

      def current_direction
        return nil unless @last_direction

        Geom::Vector3d.new(@last_direction.x, @last_direction.y, 0.0)
      end

      def draw_hover_point(view)
        return unless @hover_point

        view.line_width = 2
        color = Sketchup::Color.new(34, 87, 122)
        view.drawing_color = color
        view.draw_points([@hover_point], 12, 3, color)
      end

      def draw_existing_path(view)
        return if @chain_points.empty?

        points = @preview_end ? (@chain_points + [@preview_end]) : @chain_points
        return if points.length < 2

        view.line_width = 2
        color = Sketchup::Color.new(52, 73, 94)
        view.drawing_color = color
        view.draw(GL_LINE_STRIP, points)
        view.draw_points(@chain_points, 8, 1, color)
      end

      def draw_preview(view)
        return unless @preview_data

        footprint = @preview_data[:footprint]
        top = @preview_data[:top]
        loop_footprint = footprint + [footprint.first]
        loop_top = top + [top.first]
        columns = []

        footprint.each_with_index do |point, index|
          columns << point
          columns << top[index]
        end

        view.drawing_color = Sketchup::Color.new(194, 116, 53, 70)
        view.draw(GL_QUADS, footprint)

        view.line_width = 2
        view.drawing_color = Sketchup::Color.new(128, 67, 24)
        view.draw(GL_LINE_STRIP, loop_footprint)
        view.draw(GL_LINE_STRIP, loop_top)
        view.draw(GL_LINES, columns)

        view.drawing_color = Sketchup::Color.new(32, 32, 32)
        view.draw(GL_LINES, [@last_point, @preview_end])
        draw_preview_label(view)
      end

      def draw_preview_label(view)
        label = "#{Sketchup.format_length(@preview_data[:length])} | #{direction_label(@preview_data[:vector])}"
        text_point = @preview_data[:midpoint].offset(Z_AXIS, 10.cm)
        view.draw_text(text_point, label)
      end

      def direction_label(vector)
        if Settings.current[:ortho_mode]
          if vector.x.abs >= vector.y.abs
            vector.x >= 0 ? '+X' : '-X'
          else
            vector.y >= 0 ? '+Y' : '-Y'
          end
        else
          angle = Math.atan2(vector.y, vector.x) * 180.0 / Math::PI
          "#{angle.round(1)} deg"
        end
      end

      def update_status(prompt)
        Sketchup.set_status_text(prompt, SB_PROMPT)
        Sketchup.set_status_text('Comprimento', SB_VCB_LABEL)
        update_vcb
      end

      def update_vcb
        value = @preview_data ? Sketchup.format_length(@preview_data[:length]) : ''
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
