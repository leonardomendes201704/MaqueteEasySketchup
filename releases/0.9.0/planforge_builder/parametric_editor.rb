module LeonardoLabs
  module PlanForgeBuilder
    module ParametricEditor
      extend self

      def selection_state(model = Sketchup.active_model)
        entity = selected_entity(model.selection)
        return empty_selection_state unless entity

        room_token = GeometryBuilder.room_token(entity)
        snapshot = room_token ? RoomRegenerator.room_snapshot(model, room_token) : nil

        if GeometryBuilder.wall_group?(entity)
          wall = GeometryBuilder.wall_info(entity)
          settings = GeometryBuilder.entity_settings(entity)
          return empty_selection_state('Nao foi possivel ler a parede selecionada.') unless wall

          openings = GeometryBuilder.opening_records(entity).each_with_index.map do |record, index|
            opening_state(record, wall, index)
          end

          {
            :available => true,
            :entity_type => 'wall',
            :title => 'Parede selecionada',
            :hint => 'Edite os parametros abaixo e regenere o comodo para recalcular piso, rodape e encontros.',
            :room => room_state(snapshot),
            :wall => {
              :length_cm => to_cm(wall[:length]),
              :wall_thickness_cm => settings[:wall_thickness_cm],
              :wall_height_cm => settings[:wall_height_cm],
              :alignment => settings[:alignment],
              :openings => openings
            }
          }
        elsif snapshot
          {
            :available => true,
            :entity_type => 'room',
            :title => 'Comodo selecionado',
            :hint => 'Selecione uma parede do plugin para editar portas ou janelas especificas.',
            :room => room_state(snapshot)
          }
        else
          empty_selection_state('Selecione uma parede, piso ou rodape criado pelo PlanForge Builder.')
        end
      end

      def apply_wall_edits(model, selection, payload)
        wall = selected_wall(selection)
        raise ArgumentError, 'Selecione uma parede do PlanForge Builder para editar.' unless wall

        overrides = filtered_settings_payload(payload)
        settings = GeometryBuilder.entity_settings(wall).merge(overrides)
        settings = Settings.sanitize(settings)
        wall_info = GeometryBuilder.wall_info(wall)
        raise ArgumentError, 'Nao foi possivel ler os dados parametricos da parede.' unless wall_info

        model.start_operation('PlanForge Builder - Editar parede', true)
        if (room_token = GeometryBuilder.room_token(wall))
          snapshot = RoomRegenerator.room_snapshot(model, room_token)
          index = snapshot[:walls].index(wall)
          raise ArgumentError, 'Nao foi possivel localizar a parede dentro do comodo.' unless index

          rebuild_wall_from_snapshot(snapshot, index, settings)
          refresh_neighbor_walls(snapshot, index)
          model.commit_operation
          'Parede atualizada. Use Regenerar comodo para recalcular piso, rodape e todo o contorno.'
        else
          GeometryBuilder.rebuild_wall_with_openings(
            wall,
            wall_info[:start_point],
            wall_info[:end_point],
            settings,
            nil,
            nil,
            GeometryBuilder.opening_records(wall)
          )
          model.commit_operation
          'Parede atualizada.'
        end
      rescue StandardError => error
        model.abort_operation rescue nil
        raise error
      end

      def apply_opening_edits(model, selection, payload)
        wall = selected_wall(selection)
        raise ArgumentError, 'Selecione a parede que contem a abertura a editar.' unless wall

        wall_info = GeometryBuilder.wall_info(wall)
        raise ArgumentError, 'Nao foi possivel ler os dados da parede selecionada.' unless wall_info

        opening_id = payload.to_h['id'].to_s
        records = GeometryBuilder.opening_records(wall)
        record = records.find { |item| item[:id].to_s == opening_id }
        raise ArgumentError, 'Selecione uma porta ou janela da lista antes de aplicar.' unless record

        updated_record = update_opening_record(record, wall_info, payload)
        updated_records = records.map do |item|
          item[:id].to_s == opening_id ? updated_record : item
        end

        model.start_operation('PlanForge Builder - Editar abertura', true)
        GeometryBuilder.store_opening_records(wall, updated_records)

        if GeometryBuilder.room_token(wall)
          RoomRegenerator.regenerate_for_entity(model, wall, GeometryBuilder.entity_settings(wall))
          model.commit_operation
          "#{label_for_kind(record[:kind])} atualizada e comodo regenerado."
        else
          GeometryBuilder.rebuild_wall_with_openings(
            wall,
            wall_info[:start_point],
            wall_info[:end_point],
            GeometryBuilder.entity_settings(wall),
            nil,
            nil,
            updated_records
          )
          model.commit_operation
          "#{label_for_kind(record[:kind])} atualizada."
        end
      rescue StandardError => error
        model.abort_operation rescue nil
        raise error
      end

      def regenerate_selected_room(model, selection)
        entity = selected_room_entity(selection)
        raise ArgumentError, 'Selecione uma parede, piso ou rodape de um comodo criado pelo PlanForge Builder.' unless entity

        room_settings = GeometryBuilder.wall_group?(entity) ? GeometryBuilder.entity_settings(entity) : nil

        model.start_operation('PlanForge Builder - Regenerar comodo', true)
        RoomRegenerator.regenerate_for_entity(model, entity, room_settings)
        model.commit_operation
        'Comodo regenerado.'
      rescue StandardError => error
        model.abort_operation rescue nil
        raise error
      end

      private

      def empty_selection_state(message = 'Selecione uma parede do plugin para editar parametros e aberturas.')
        {
          :available => false,
          :entity_type => 'none',
          :title => 'Editor parametrico',
          :hint => message
        }
      end

      def selected_entity(selection)
        entities = selection.to_a
        entities.find { |entity| GeometryBuilder.wall_group?(entity) } ||
          entities.find { |entity| GeometryBuilder.room_token(entity) }
      end

      def selected_wall(selection)
        selection.to_a.find { |entity| GeometryBuilder.wall_group?(entity) }
      end

      def selected_room_entity(selection)
        selected_entity(selection)
      end

      def room_state(snapshot)
        return nil unless snapshot

        {
          :wall_count => snapshot[:walls].length,
          :has_floor => !snapshot[:floors].empty?,
          :has_baseboard => !snapshot[:baseboards].empty?,
          :can_regenerate => !snapshot[:walls].empty?
        }
      end

      def opening_state(record, wall, index)
        {
          :id => record[:id],
          :label => "#{label_for_kind(record[:kind])} #{index + 1}",
          :kind => record[:kind],
          :width_cm => to_cm(record[:opening_width]),
          :height_cm => to_cm(record[:top_z] - record[:bottom_z]),
          :center_distance_cm => to_cm(record[:center_distance]),
          :bottom_height_cm => to_cm(record[:bottom_z] - wall[:base_z]),
          :top_height_cm => to_cm(record[:top_z] - wall[:base_z])
        }
      end

      def label_for_kind(kind)
        kind.to_s == 'window' ? 'Janela' : 'Porta'
      end

      def to_cm(length)
        (length.to_f / 1.cm).round(2)
      end

      def filtered_settings_payload(payload)
        normalized = symbolize(payload)
        allowed = {}
        %i[wall_thickness_cm wall_height_cm alignment].each do |key|
          allowed[key] = normalized[key] if normalized.key?(key)
        end
        allowed
      end

      def rebuild_wall_from_snapshot(snapshot, index, settings = nil)
        walls = snapshot[:walls]
        contour = GeometryBuilder.normalized_contour_points(snapshot[:contour])
        wall = walls[index]
        wall_settings = settings || GeometryBuilder.entity_settings(wall)
        prev_point = contour[(index - 1) % contour.length]
        next_point = contour[(index + 2) % contour.length]

        GeometryBuilder.rebuild_wall_with_openings(
          wall,
          contour[index],
          contour[(index + 1) % contour.length],
          wall_settings,
          prev_point,
          next_point,
          GeometryBuilder.opening_records(wall)
        )
      end

      def refresh_neighbor_walls(snapshot, index)
        return if snapshot[:walls].length < 2

        neighbors = [((index - 1) % snapshot[:walls].length), ((index + 1) % snapshot[:walls].length)].uniq
        neighbors.each do |neighbor_index|
          rebuild_wall_from_snapshot(snapshot, neighbor_index)
        end
      end

      def update_opening_record(record, wall_info, payload)
        normalized = symbolize(payload)
        width = read_numeric(normalized[:opening_width_cm], to_cm(record[:opening_width]))
        height = read_numeric(normalized[:opening_height_cm], to_cm(record[:top_z] - record[:bottom_z]))
        center_distance = read_numeric(normalized[:center_distance_cm], to_cm(record[:center_distance]))
        bottom_height = read_numeric(normalized[:bottom_height_cm], to_cm(record[:bottom_z] - wall_info[:base_z]))

        width_length = width.to_f.cm
        height_length = height.to_f.cm
        center_length = center_distance.to_f.cm

        bottom_z = if record[:kind].to_s == 'window'
                     wall_info[:base_z] + bottom_height.to_f.cm
                   else
                     wall_info[:base_z]
                   end

        {
          :id => record[:id],
          :kind => record[:kind],
          :center_distance => center_length,
          :opening_width => width_length,
          :bottom_z => bottom_z,
          :top_z => bottom_z + height_length
        }
      end

      def read_numeric(value, fallback)
        parsed = value.is_a?(Numeric) ? value.to_f : value.to_s.strip.tr(',', '.')
        parsed = Float(parsed)
        parsed.finite? ? parsed : fallback
      rescue StandardError
        fallback
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
