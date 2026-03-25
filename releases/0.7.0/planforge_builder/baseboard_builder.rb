module LeonardoLabs
  module PlanForgeBuilder
    module BaseboardBuilder
      extend self

      TOLERANCE = 1.mm

      def build_for_room(model, contour_points, wall_groups, settings = Settings.to_h, room_token = nil, replace_existing = true)
        sanitized = Settings.sanitize(settings)
        contour = GeometryBuilder.normalized_contour_points(contour_points)
        walls = Array(wall_groups).select { |group| GeometryBuilder.wall_group?(group) }
        return nil if contour.length < 3 || walls.empty?

        room_token ||= GeometryBuilder.assign_room_metadata(walls, contour, sanitized)
        remove_existing_for_room(model, room_token) if replace_existing && room_token

        group = model.active_entities.add_group
        group.name = 'PlanForge Baseboard'
        group.set_attribute(PLUGIN_ID, 'entity_type', 'baseboard')
        sanitized.each do |key, value|
          group.set_attribute(PLUGIN_ID, key.to_s, value)
        end
        GeometryBuilder.tag_room_entity(group, contour, sanitized, room_token)
        group.set_attribute(PLUGIN_ID, 'source_wall_ids', JSON.generate(walls.map(&:persistent_id)))

        baseboard_height = sanitized[:baseboard_height_cm].to_f.cm
        baseboard_depth = sanitized[:baseboard_depth_cm].to_f.cm
        if baseboard_height <= TOLERANCE || baseboard_depth <= TOLERANCE
          MaterialManager.apply_to_entity(group, :baseboard, sanitized)
          return group
        end

        inner_outline = GeometryBuilder.floor_outline_points(contour, sanitized)
        interior_offset = GeometryBuilder.room_interior_offset_distance(contour, sanitized)
        base_z = room_baseboard_base_z(model, room_token, walls)
        group.set_attribute(PLUGIN_ID, 'base_z', base_z.to_f)

        walls.each_with_index do |wall_group, index|
          wall = GeometryBuilder.wall_info(wall_group)
          next unless wall

          inner_start = inner_outline[index]
          inner_end = inner_outline[(index + 1) % inner_outline.length]
          build_wall_baseboards(
            group.entities,
            wall_group,
            wall,
            inner_start,
            inner_end,
            interior_offset,
            base_z,
            baseboard_height,
            baseboard_depth
          )
        end

        MaterialManager.apply_to_entity(group, :baseboard, sanitized)
        group
      end

      def build_from_selection(model, selection, settings = Settings.to_h)
        entities = selection.to_a
        room_tokens = entities.map { |entity| GeometryBuilder.room_token(entity) }.compact.uniq
        return [] if room_tokens.empty?

        room_tokens.each_with_object([]) do |room_token, groups|
          room_entities = room_entities_for_token(model, room_token)
          walls = room_entities[:walls]
          contour = room_entities[:contour]
          next if walls.empty? || contour.length < 3

          group = build_for_room(model, contour, walls, settings, room_token, true)
          groups << group if group
        end
      end

      private

      def remove_existing_for_room(model, room_token)
        return unless room_token

        existing = model.active_entities.grep(Sketchup::Group).select do |group|
          group.get_attribute(PLUGIN_ID, 'entity_type') == 'baseboard' &&
            GeometryBuilder.room_token(group) == room_token
        end
        model.active_entities.erase_entities(existing) unless existing.empty?
      end

      def room_entities_for_token(model, room_token)
        groups = model.active_entities.grep(Sketchup::Group)
        walls = groups.select do |group|
          GeometryBuilder.wall_group?(group) && GeometryBuilder.room_token(group) == room_token
        end.sort_by { |group| group.get_attribute(PLUGIN_ID, 'room_sequence', 0).to_i }

        contour_source = walls.find { |group| !GeometryBuilder.room_contour(group).empty? }
        contour_source ||= groups.find { |group| GeometryBuilder.room_token(group) == room_token && !GeometryBuilder.room_contour(group).empty? }

        {
          :walls => walls,
          :contour => contour_source ? GeometryBuilder.room_contour(contour_source) : []
        }
      end

      def build_wall_baseboards(entities, wall_group, wall, inner_start, inner_end, interior_offset, base_z, height, depth)
        face_origin = offset_point(wall[:start_point], wall[:left_axis], interior_offset)
        segment_start = project_distance(inner_start, face_origin, wall[:axis])
        segment_end = project_distance(inner_end, face_origin, wall[:axis])
        return if (segment_end - segment_start).abs <= TOLERANCE

        range_start, range_end = [segment_start, segment_end].minmax
        free_intervals(wall_group, wall, range_start, range_end, base_z, height).each do |interval_start, interval_end|
          next if (interval_end - interval_start) <= TOLERANCE

          segment_group = entities.add_group
          segment_group.name = 'PlanForge Baseboard Segment'
          segment_group.set_attribute(PLUGIN_ID, 'entity_type', 'baseboard_segment')
          segment_group.set_attribute(PLUGIN_ID, 'source_wall_id', wall_group.persistent_id)

          face_start = offset_point(face_origin, wall[:axis], interval_start)
          face_end = offset_point(face_origin, wall[:axis], interval_end)
          face_start.z = base_z
          face_end.z = base_z
          inside_direction = interior_offset.negative? ? -1.0 : 1.0
          outer_start = offset_point(face_start, wall[:left_axis], depth * inside_direction)
          outer_end = offset_point(face_end, wall[:left_axis], depth * inside_direction)

          face = segment_group.entities.add_face([face_start, face_end, outer_end, outer_start])
          next unless face

          face.reverse! if face.normal.z < 0
          face.pushpull(height)
        end
      end

      def free_intervals(wall_group, wall, range_start, range_end, base_z, baseboard_height)
        blockers = GeometryBuilder.opening_records(wall_group).each_with_object([]) do |opening, intervals|
          next unless opening[:bottom_z] <= (base_z + baseboard_height + TOLERANCE)

          opening_start = opening[:center_distance] - (opening[:opening_width] / 2.0)
          opening_end = opening[:center_distance] + (opening[:opening_width] / 2.0)
          interval_start = [opening_start, range_start].max
          interval_end = [opening_end, range_end].min
          next if interval_end <= interval_start

          intervals << [interval_start, interval_end]
        end

        subtract_intervals([[range_start, range_end]], blockers.sort_by(&:first))
      end

      def room_baseboard_base_z(model, room_token, walls)
        floor_top = room_floor_top_z(model, room_token)
        return floor_top if floor_top

        walls.map { |wall| GeometryBuilder.wall_info(wall) }
             .compact
             .map { |wall| wall[:base_z] }
             .min || 0.0
      end

      def room_floor_top_z(model, room_token)
        return nil unless room_token

        floors = model.active_entities.grep(Sketchup::Group).select do |group|
          group.get_attribute(PLUGIN_ID, 'entity_type') == 'floor' &&
            GeometryBuilder.room_token(group) == room_token
        end
        return nil if floors.empty?

        floors.map { |group| group.bounds.max.z }.max
      end

      def subtract_intervals(base_intervals, blockers)
        blockers.reduce(base_intervals) do |intervals, blocker|
          intervals.flat_map do |interval|
            subtract_interval(interval, blocker)
          end
        end
      end

      def subtract_interval(interval, blocker)
        interval_start, interval_end = interval
        blocker_start, blocker_end = blocker
        return [interval] if blocker_end <= interval_start || blocker_start >= interval_end

        result = []
        result << [interval_start, blocker_start] if blocker_start > interval_start
        result << [blocker_end, interval_end] if blocker_end < interval_end
        result
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
    end
  end
end
