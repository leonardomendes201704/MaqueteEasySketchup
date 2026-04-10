module LeonardoLabs
  module PlanForgeBuilder
    module ParametricEditor
      extend self

      def selection_state(model = Sketchup.active_model)
        entity = selected_entity(model.selection, model)
        return empty_selection_state unless entity

        room_token = GeometryBuilder.room_token(entity)
        snapshot = room_token ? RoomRegenerator.room_snapshot(model, room_token) : nil

        if GeometryBuilder.wall_group?(entity)
          wall = GeometryBuilder.wall_info(entity)
          settings = GeometryBuilder.entity_settings(entity)
          quantities = GeometryBuilder.wall_quantities(entity)
          return empty_selection_state('Nao foi possivel ler a parede selecionada.') unless wall

          openings = GeometryBuilder.opening_records(entity).each_with_index.map do |record, index|
            opening_state(record, wall, index)
          end

          {
            :available => true,
            :entity_type => 'wall',
            :title => 'Parede selecionada',
            :hint => 'Edite os parametros abaixo, gere a maquete em blocos quando quiser e regenere o comodo para recalcular o restante.',
            :room => room_state(snapshot),
            :wall => {
              :length_cm => to_cm(wall[:length]),
              :wall_thickness_cm => settings[:wall_thickness_cm],
              :wall_height_cm => settings[:wall_height_cm],
              :alignment => settings[:alignment],
              :block_estimate => block_estimate_state(quantities),
              :mortar_estimate => mortar_estimate_state(quantities),
              :structure_estimate => structure_estimate_state(entity),
              :block_conversion => block_conversion_state(model, entity),
              :openings => openings
            }
          }
        elsif snapshot
          {
            :available => true,
            :entity_type => 'room',
            :title => 'Comodo selecionado',
            :hint => 'Selecione uma parede do plugin para editar portas, janelas ou converter a parede em blocos.',
            :room => room_state(snapshot)
          }
        else
          empty_selection_state('Selecione uma parede, piso, rodape ou alvenaria em blocos criado pelo PlanForge Builder.')
        end
      end

      def apply_wall_edits(model, selection, payload)
        wall = selected_wall(selection, model)
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
          WallBlockBuilder.refresh_for_walls(model, snapshot[:walls])
          focus_entity_for_wall(model, wall)
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
          WallBlockBuilder.refresh_for_wall(model, wall)
          focus_entity_for_wall(model, wall)
          model.commit_operation
          'Parede atualizada.'
        end
      rescue StandardError => error
        model.abort_operation rescue nil
        raise error
      end

      def apply_opening_edits(model, selection, payload)
        wall = selected_wall(selection, model)
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
          focus_entity_for_wall(model, wall)
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
          WallBlockBuilder.refresh_for_wall(model, wall)
          focus_entity_for_wall(model, wall)
          model.commit_operation
          "#{label_for_kind(record[:kind])} atualizada."
        end
      rescue StandardError => error
        model.abort_operation rescue nil
        raise error
      end

      def regenerate_selected_room(model, selection)
        entity = selected_room_entity(selection, model)
        raise ArgumentError, 'Selecione uma parede, piso, rodape ou alvenaria em blocos de um comodo criado pelo PlanForge Builder.' unless entity

        wall = selected_wall(selection, model)
        room_settings = wall ? GeometryBuilder.entity_settings(wall) : nil

        model.start_operation('PlanForge Builder - Regenerar comodo', true)
        RoomRegenerator.regenerate_for_entity(model, entity, room_settings)
        focus_entity_for_wall(model, wall) if wall&.valid?
        model.commit_operation
        'Comodo regenerado.'
      rescue StandardError => error
        model.abort_operation rescue nil
        raise error
      end

      def convert_selected_wall_to_blocks(model, selection)
        wall = selected_wall(selection, model)
        raise ArgumentError, 'Selecione uma parede fisica do PlanForge Builder para converter em blocos.' unless GeometryBuilder.physical_wall_group?(wall)

        model.start_operation('PlanForge Builder - Converter parede em blocos', true)
        block_group = WallBlockBuilder.build_for_wall(model, wall, GeometryBuilder.entity_settings(wall), true)
        select_entity(model, block_group || wall)
        model.commit_operation
        'Parede convertida em blocos com estrutura.'
      rescue StandardError => error
        model.abort_operation rescue nil
        raise error
      end

      def remove_selected_wall_blocks(model, selection)
        wall = selected_wall(selection, model)
        raise ArgumentError, 'Selecione uma parede do PlanForge Builder para remover a alvenaria em blocos.' unless wall

        model.start_operation('PlanForge Builder - Remover parede em blocos', true)
        WallBlockBuilder.remove_for_wall(model, wall)
        select_entity(model, wall)
        model.commit_operation
        'Alvenaria em blocos removida.'
      rescue StandardError => error
        model.abort_operation rescue nil
        raise error
      end

      private

      def empty_selection_state(message = 'Selecione uma parede do plugin para editar parametros, aberturas ou converter em blocos.')
        {
          :available => false,
          :entity_type => 'none',
          :title => 'Editor parametrico',
          :hint => message
        }
      end

      def selected_entity(selection, model = Sketchup.active_model)
        wall = selected_wall(selection, model)
        return wall if wall

        selection.to_a.find { |entity| GeometryBuilder.room_token(entity) }
      end

      def selected_wall(selection, model = Sketchup.active_model)
        selection.to_a.each do |entity|
          wall = WallBlockBuilder.host_wall_for_entity(model, entity)
          return wall if GeometryBuilder.wall_group?(wall)
        end

        nil
      end

      def selected_room_entity(selection, model = Sketchup.active_model)
        selected_entity(selection, model)
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

      def block_estimate_state(quantities)
        return nil unless quantities

        {
          :block_type => quantities[:block_type],
          :gross_area_m2 => quantities[:gross_area_m2].round(2),
          :opening_area_m2 => quantities[:opening_area_m2].round(2),
          :net_area_m2 => quantities[:net_area_m2].round(2),
          :block_count => quantities[:block_count].to_i,
          :warning => quantities[:block_warning].to_s
        }
      end

      def mortar_estimate_state(quantities)
        return nil unless quantities

        {
          :mix => quantities[:mortar_mix],
          :volume_m3 => quantities[:mortar_volume_m3].round(3),
          :cement_kg => quantities[:mortar_cement_kg].round(1),
          :lime_kg => quantities[:mortar_lime_kg].round(1),
          :sand_m3 => quantities[:mortar_sand_m3].round(3),
          :note => quantities[:mortar_note].to_s
        }
      end

      def block_conversion_state(model, wall)
        state = WallBlockBuilder.conversion_state(model, wall)
        {
          :has_block_conversion => !!state[:has_block_conversion],
          :block_conversion_hidden_host => !!state[:block_conversion_hidden_host],
          :block_conversion_warning => state[:block_conversion_warning].to_s,
          :button_label => state[:button_label].to_s,
          :can_remove_block_conversion => !!state[:can_remove_block_conversion]
        }
      end

      def structure_estimate_state(wall)
        estimate = WallBlockBuilder.structure_estimate(wall)
        return nil unless estimate

        {
          :column_count => estimate[:column_count].to_i,
          :bond_beam_length_m => estimate[:bond_beam_length_m].round(2),
          :lintel_count => estimate[:lintel_count].to_i,
          :lintel_length_m => estimate[:lintel_length_m].round(2),
          :sill_beam_count => estimate[:sill_beam_count].to_i,
          :sill_beam_length_m => estimate[:sill_beam_length_m].round(2),
          :column_volume_m3 => estimate[:column_volume_m3].round(3),
          :bond_beam_volume_m3 => estimate[:bond_beam_volume_m3].round(3),
          :lintel_volume_m3 => estimate[:lintel_volume_m3].round(3),
          :sill_beam_volume_m3 => estimate[:sill_beam_volume_m3].round(3),
          :total_concrete_volume_m3 => estimate[:total_concrete_volume_m3].round(3),
          :warning => estimate[:warning_text].to_s
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

      def focus_entity_for_wall(model, wall)
        return unless wall&.valid?

        select_entity(model, WallBlockBuilder.block_group_for_wall(model, wall) || wall)
      end

      def select_entity(model, entity)
        return unless entity&.valid?

        model.selection.clear
        model.selection.add(entity)
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
