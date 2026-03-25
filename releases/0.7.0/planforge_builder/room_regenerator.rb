module LeonardoLabs
  module PlanForgeBuilder
    module RoomRegenerator
      extend self

      def room_snapshot(model, room_token)
        groups = model.active_entities.grep(Sketchup::Group)
        walls = groups.select do |group|
          GeometryBuilder.wall_group?(group) && GeometryBuilder.room_token(group) == room_token
        end.sort_by { |group| group.get_attribute(PLUGIN_ID, 'room_sequence', 0).to_i }

        contour_source = walls.find { |group| !GeometryBuilder.room_contour(group).empty? }
        contour_source ||= groups.find do |group|
          GeometryBuilder.room_token(group) == room_token && !GeometryBuilder.room_contour(group).empty?
        end

        {
          :room_token => room_token,
          :walls => walls,
          :contour => contour_source ? GeometryBuilder.room_contour(contour_source) : [],
          :floors => groups.select do |group|
            group.get_attribute(PLUGIN_ID, 'entity_type') == 'floor' && GeometryBuilder.room_token(group) == room_token
          end,
          :baseboards => groups.select do |group|
            group.get_attribute(PLUGIN_ID, 'entity_type') == 'baseboard' && GeometryBuilder.room_token(group) == room_token
          end,
          :settings => walls.first ? GeometryBuilder.entity_settings(walls.first) : Settings.to_h
        }
      end

      def regenerate_for_entity(model, entity, room_settings = nil)
        room_token = GeometryBuilder.room_token(entity)
        return nil unless room_token

        regenerate_room(model, room_token, room_settings)
      end

      def regenerate_room(model, room_token, room_settings = nil)
        snapshot = room_snapshot(model, room_token)
        walls = snapshot[:walls]
        contour = GeometryBuilder.normalized_contour_points(snapshot[:contour])
        raise ArgumentError, 'Selecione um comodo valido do PlanForge Builder para regenerar.' if walls.empty? || contour.length < 3

        settings = Settings.sanitize(snapshot[:settings].merge(symbolize(room_settings)))
        openings_by_wall = walls.each_with_object({}) do |wall, result|
          result[wall.persistent_id] = GeometryBuilder.opening_records(wall)
        end

        walls.each_with_index do |wall, index|
          prev_point, next_point = adjacent_points(contour, index)
          GeometryBuilder.rebuild_wall_with_openings(
            wall,
            contour[index],
            contour[(index + 1) % contour.length],
            settings,
            prev_point,
            next_point,
            openings_by_wall[wall.persistent_id]
          )
        end

        GeometryBuilder.assign_room_metadata(walls, contour, settings, room_token)
        rebuild_floor(model, snapshot, contour, settings, room_token)
        rebuild_baseboard(model, snapshot, contour, walls, settings, room_token)

        room_snapshot(model, room_token)
      end

      private

      def rebuild_floor(model, snapshot, contour, settings, room_token)
        had_floor = !snapshot[:floors].empty?
        erase_groups(model, snapshot[:floors])
        return unless had_floor

        floor_group = GeometryBuilder.build_floor(model, contour, settings)
        GeometryBuilder.tag_room_entity(floor_group, contour, settings, room_token)
      end

      def rebuild_baseboard(model, snapshot, contour, walls, settings, room_token)
        had_baseboard = !snapshot[:baseboards].empty?
        erase_groups(model, snapshot[:baseboards])
        return unless had_baseboard

        BaseboardBuilder.build_for_room(model, contour, walls, settings, room_token, true)
      end

      def erase_groups(model, groups)
        valid_groups = Array(groups).select(&:valid?)
        model.active_entities.erase_entities(valid_groups) unless valid_groups.empty?
      end

      def adjacent_points(points, index)
        count = points.length
        prev_point = points[(index - 1) % count]
        next_point = points[(index + 2) % count]
        [prev_point, next_point]
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
