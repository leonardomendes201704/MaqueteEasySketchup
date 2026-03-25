module LeonardoLabs
  module PlanForgeBuilder
    module RoomReconciler
      extend self

      TOLERANCE = 1.mm

      def reconcile_room(model, room_token, room_settings = nil)
        snapshot = RoomRegenerator.room_snapshot(model, room_token)
        walls = snapshot[:walls]
        contour = GeometryBuilder.normalized_contour_points(snapshot[:contour])
        return snapshot if walls.empty? || contour.length < 3

        settings = Settings.sanitize(snapshot[:settings].merge(symbolize(room_settings)))
        inner_outline = GeometryBuilder.floor_outline_points(contour, settings)
        host_walls = model.active_entities.grep(Sketchup::Group).select do |group|
          GeometryBuilder.physical_wall_group?(group) && !walls.include?(group)
        end

        plans = walls.each_with_index.map do |wall_group, index|
          {
            :wall_group => wall_group,
            :shared_host => find_shared_host(host_walls, inner_outline[index], inner_outline[(index + 1) % inner_outline.length]),
            :openings => GeometryBuilder.opening_records(wall_group)
          }
        end

        plans.each_with_index do |plan, index|
          wall_group = plan[:wall_group]
          edge_start = contour[index]
          edge_end = contour[(index + 1) % contour.length]
          edge_axis = flat_direction(edge_start, edge_end)
          edge_axis.normalize!

          if plan[:shared_host]
            GeometryBuilder.rebuild_proxy_wall(
              wall_group,
              edge_start,
              edge_end,
              settings,
              plan[:shared_host].persistent_id
            )
            next
          end

          previous_plan = plans[(index - 1) % plans.length]
          next_plan = plans[(index + 1) % plans.length]
          actual_start = previous_plan[:shared_host] ? trim_point_on_axis(edge_start, edge_axis, inner_outline[index]) : edge_start
          actual_end = next_plan[:shared_host] ? trim_point_on_axis(edge_start, edge_axis, inner_outline[(index + 1) % inner_outline.length]) : edge_end
          previous_point = previous_plan[:shared_host] ? nil : contour[(index - 1) % contour.length]
          next_point = next_plan[:shared_host] ? nil : contour[(index + 2) % contour.length]

          GeometryBuilder.rebuild_wall_with_openings(
            wall_group,
            actual_start,
            actual_end,
            settings,
            previous_point,
            next_point,
            plan[:openings]
          )
        end

        GeometryBuilder.assign_room_metadata(walls, contour, settings, room_token)
        RoomRegenerator.room_snapshot(model, room_token)
      end

      private

      def find_shared_host(host_walls, edge_start, edge_end)
        edge_axis = flat_direction(edge_start, edge_end)
        return nil if edge_axis.length <= TOLERANCE

        edge_axis.normalize!
        edge_length = edge_start.distance(edge_end)

        candidates = host_walls.each_with_object([]) do |host_group, result|
          wall = GeometryBuilder.wall_info(host_group)
          next unless wall
          next unless parallel_2d?(wall[:axis], edge_axis)

          score = shared_face_score(wall, edge_start, edge_end, edge_length)
          next unless score

          result << [host_group, score]
        end

        best = candidates.min_by { |_host_group, score| score }
        best && best.first
      end

      def shared_face_score(wall, edge_start, edge_end, edge_length)
        candidate_scores = [wall[:left_extent], -wall[:right_extent]].each_with_object([]) do |offset, result|
          face_start = offset_point(wall[:start_point], wall[:left_axis], offset)
          next unless same_support_line?(edge_start, edge_end, face_start, wall[:axis])

          start_projection = project_distance(edge_start, face_start, wall[:axis])
          end_projection = project_distance(edge_end, face_start, wall[:axis])
          overlap_start, overlap_end = [start_projection, end_projection].minmax
          next if overlap_start < -TOLERANCE || overlap_end > (wall[:length] + TOLERANCE)
          next if (overlap_end - overlap_start) < (edge_length - TOLERANCE)

          overlap_margin = overlap_start.abs + (wall[:length] - overlap_end).abs
          line_error = point_line_distance(edge_start, face_start, wall[:axis]) +
                       point_line_distance(edge_end, face_start, wall[:axis])
          result << (overlap_margin + line_error)
        end

        candidate_scores.min
      end

      def same_support_line?(edge_start, edge_end, face_start, axis)
        point_line_distance(edge_start, face_start, axis) <= TOLERANCE &&
          point_line_distance(edge_end, face_start, axis) <= TOLERANCE
      end

      def flat_direction(start_point, end_point)
        vector = end_point - start_point
        Geom::Vector3d.new(vector.x, vector.y, 0.0)
      end

      def parallel_2d?(vector_a, vector_b)
        cross = (vector_a.x * vector_b.y) - (vector_a.y * vector_b.x)
        cross.abs <= 1.0e-6
      end

      def point_line_distance(point, line_point, line_direction)
        numerator = ((point.x - line_point.x) * line_direction.y) - ((point.y - line_point.y) * line_direction.x)
        numerator.abs / [line_direction.length, 1.0e-9].max
      end

      def project_distance(point, origin, axis)
        (point - origin).dot(axis)
      end

      def offset_point(point, vector, distance)
        Geom::Point3d.new(
          point.x + (vector.x * distance),
          point.y + (vector.y * distance),
          point.z + (vector.z * distance)
        )
      end

      def trim_point_on_axis(origin, axis, target_point)
        offset_point(origin, axis, project_distance(target_point, origin, axis))
      end

      def symbolize(payload)
        return {} unless payload.is_a?(Hash)

        payload.each_with_object({}) do |(key, value), result|
          result[key.to_s.strip.downcase.gsub(/\s+/, '_').to_sym] = value
        end
      end
    end
  end
end
