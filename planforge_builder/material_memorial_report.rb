module LeonardoLabs
  module PlanForgeBuilder
    module MaterialMemorialReport
      extend self

      REPORT_TITLE = 'Memorial Descritivo de Materiais e Quantitativos'.freeze
      SCOPE_NOTE = 'Documento restrito a alvenaria convertida em blocos no modelo atual.'.freeze
      STRUCTURAL_NOTE = 'Memorial quantitativo do plugin, sem detalhamento estrutural executivo.'.freeze

      def build(model = Sketchup.active_model, settings = Settings.to_h)
        raise ArgumentError, 'Nao foi possivel acessar o modelo atual do SketchUp.' unless model

        walls = converted_walls(model)
        raise ArgumentError, 'Nao ha paredes convertidas em blocos no modelo atual.' if walls.empty?

        groups = build_groups(model, walls)
        {
          :title => REPORT_TITLE,
          :model_name => model_label(model),
          :model_path => model.path.to_s,
          :issued_at => Time.now,
          :header => build_header(settings),
          :criteria => criteria_lines,
          :groups => groups,
          :summary => overall_summary(groups)
        }
      end

      def converted_walls(model = Sketchup.active_model)
        return [] unless model

        model.active_entities.grep(Sketchup::Group).select do |group|
          converted_wall?(model, group)
        end
      end

      private

      def converted_wall?(model, wall_group)
        return false unless wall_group&.valid?
        return false unless GeometryBuilder.physical_wall_group?(wall_group)

        block_group = WallBlockBuilder.block_group_for_wall(model, wall_group)
        return true if block_group&.valid?

        wall_group.get_attribute(PLUGIN_ID, 'has_block_conversion', false) && wall_group.hidden?
      end

      def build_header(settings)
        payload = Settings.sanitize(settings)
        {
          :project_name => payload[:memorial_project_name].to_s,
          :client_name => payload[:memorial_client_name].to_s,
          :site_name => payload[:memorial_site_name].to_s,
          :responsible_name => payload[:memorial_responsible_name].to_s,
          :responsible_registry => payload[:memorial_responsible_registry].to_s,
          :notes => payload[:memorial_notes].to_s
        }
      end

      def criteria_lines
        [
          "Bloco adotado: #{GeometryBuilder::BLOCK_TYPE}.",
          'Junta adotada: 1 cm.',
          'Modulo de alvenaria adotado: 20x40 cm.',
          "Traco de argamassa adotado: #{GeometryBuilder::MORTAR_MIX}.",
          GeometryBuilder::MORTAR_NOTE,
          SCOPE_NOTE,
          STRUCTURAL_NOTE
        ]
      end

      def build_groups(model, walls)
        room_tokens = []
        room_walls = Hash.new { |hash, key| hash[key] = [] }
        standalone_walls = []

        Array(walls).each do |wall|
          token = GeometryBuilder.room_token(wall).to_s
          if token.empty?
            standalone_walls << wall
          else
            room_tokens << token unless room_walls.key?(token)
            room_walls[token] << wall
          end
        end

        groups = room_tokens.each_with_index.map do |token, index|
          walls_in_group = room_walls[token].sort_by do |wall|
            [wall.get_attribute(PLUGIN_ID, 'room_sequence', 9_999).to_i, wall.persistent_id]
          end
          build_group(model, walls_in_group, "Comodo #{format('%02d', index + 1)}", token)
        end

        unless standalone_walls.empty?
          groups << build_group(
            model,
            standalone_walls.sort_by(&:persistent_id),
            'Paredes convertidas avulsas',
            nil
          )
        end

        groups
      end

      def build_group(model, walls, label, room_token)
        entries = Array(walls).each_with_index.map do |wall, index|
          build_wall_entry(model, wall, index + 1)
        end

        {
          :label => label,
          :room_token => room_token.to_s,
          :wall_count => entries.length,
          :walls => entries,
          :totals => build_group_totals(model, walls, entries)
        }
      end

      def build_wall_entry(model, wall, index)
        wall_info = GeometryBuilder.wall_info(wall)
        quantities = GeometryBuilder.wall_quantities(wall)
        raise ArgumentError, 'Nao foi possivel ler os quantitativos da parede convertida.' unless wall_info && quantities

        structure = WallBlockBuilder.structure_estimate(wall) || empty_structure_estimate
        warnings = wall_warnings(model, wall, quantities, structure)

        {
          :id => wall.persistent_id,
          :label => wall_label(wall, index),
          :length_m => meters(wall_info[:length]),
          :height_m => meters(wall_info[:height]),
          :gross_area_m2 => quantities[:gross_area_m2].to_f,
          :opening_area_m2 => quantities[:opening_area_m2].to_f,
          :net_area_m2 => quantities[:net_area_m2].to_f,
          :block_type => quantities[:block_type].to_s,
          :block_count => quantities[:block_count].to_i,
          :mortar_mix => quantities[:mortar_mix].to_s,
          :mortar_volume_m3 => quantities[:mortar_volume_m3].to_f,
          :mortar_cement_kg => quantities[:mortar_cement_kg].to_f,
          :mortar_lime_kg => quantities[:mortar_lime_kg].to_f,
          :mortar_sand_m3 => quantities[:mortar_sand_m3].to_f,
          :column_count => structure[:column_count].to_i,
          :bond_beam_length_m => structure[:bond_beam_length_m].to_f,
          :lintel_count => structure[:lintel_count].to_i,
          :lintel_length_m => structure[:lintel_length_m].to_f,
          :sill_beam_count => structure[:sill_beam_count].to_i,
          :sill_beam_length_m => structure[:sill_beam_length_m].to_f,
          :column_volume_m3 => structure[:column_volume_m3].to_f,
          :bond_beam_volume_m3 => structure[:bond_beam_volume_m3].to_f,
          :lintel_volume_m3 => structure[:lintel_volume_m3].to_f,
          :sill_beam_volume_m3 => structure[:sill_beam_volume_m3].to_f,
          :total_concrete_volume_m3 => structure[:total_concrete_volume_m3].to_f,
          :warning_text => warnings.join(' | ')
        }
      end

      def wall_label(wall, index)
        room_sequence = wall.get_attribute(PLUGIN_ID, 'room_sequence', nil)
        return "Parede #{room_sequence.to_i + 1}" unless room_sequence.nil?

        "Parede #{format('%02d', index)}"
      end

      def wall_warnings(model, wall, quantities, structure)
        warnings = []
        warnings << quantities[:block_warning].to_s
        warnings << structure[:warning_text].to_s
        conversion_warning = WallBlockBuilder.conversion_state(model, wall)[:block_conversion_warning].to_s
        warnings << conversion_warning
        warnings.map(&:strip).reject(&:empty?).uniq
      end

      def build_group_totals(model, walls, entries)
        structural = actual_structural_totals(model, walls)
        {
          :gross_area_m2 => sum_field(entries, :gross_area_m2),
          :opening_area_m2 => sum_field(entries, :opening_area_m2),
          :net_area_m2 => sum_field(entries, :net_area_m2),
          :block_count => sum_integer_field(entries, :block_count),
          :mortar_volume_m3 => sum_field(entries, :mortar_volume_m3),
          :mortar_cement_kg => sum_field(entries, :mortar_cement_kg),
          :mortar_lime_kg => sum_field(entries, :mortar_lime_kg),
          :mortar_sand_m3 => sum_field(entries, :mortar_sand_m3)
        }.merge(structural)
      end

      def overall_summary(groups)
        {
          :group_count => Array(groups).length,
          :wall_count => Array(groups).sum { |group| group[:wall_count].to_i },
          :gross_area_m2 => Array(groups).sum { |group| group[:totals][:gross_area_m2].to_f },
          :opening_area_m2 => Array(groups).sum { |group| group[:totals][:opening_area_m2].to_f },
          :net_area_m2 => Array(groups).sum { |group| group[:totals][:net_area_m2].to_f },
          :block_count => Array(groups).sum { |group| group[:totals][:block_count].to_i },
          :mortar_volume_m3 => Array(groups).sum { |group| group[:totals][:mortar_volume_m3].to_f },
          :mortar_cement_kg => Array(groups).sum { |group| group[:totals][:mortar_cement_kg].to_f },
          :mortar_lime_kg => Array(groups).sum { |group| group[:totals][:mortar_lime_kg].to_f },
          :mortar_sand_m3 => Array(groups).sum { |group| group[:totals][:mortar_sand_m3].to_f },
          :column_count => Array(groups).sum { |group| group[:totals][:column_count].to_i },
          :bond_beam_length_m => Array(groups).sum { |group| group[:totals][:bond_beam_length_m].to_f },
          :lintel_count => Array(groups).sum { |group| group[:totals][:lintel_count].to_i },
          :lintel_length_m => Array(groups).sum { |group| group[:totals][:lintel_length_m].to_f },
          :sill_beam_count => Array(groups).sum { |group| group[:totals][:sill_beam_count].to_i },
          :sill_beam_length_m => Array(groups).sum { |group| group[:totals][:sill_beam_length_m].to_f },
          :total_concrete_volume_m3 => Array(groups).sum { |group| group[:totals][:total_concrete_volume_m3].to_f }
        }
      end

      def actual_structural_totals(model, walls)
        pieces = structural_pieces_for_walls(model, walls)
        grouped = pieces.group_by do |piece|
          kind = piece.get_attribute(PLUGIN_ID, 'structural_kind').to_s
          kind == 'junction_column' ? 'column' : kind
        end

        {
          :column_count => grouped.fetch('column', []).length,
          :bond_beam_length_m => total_piece_length_m(grouped.fetch('bond_beam', [])),
          :lintel_count => grouped.fetch('lintel', []).length,
          :lintel_length_m => total_piece_length_m(grouped.fetch('lintel', [])),
          :sill_beam_count => grouped.fetch('sill_beam', []).length,
          :sill_beam_length_m => total_piece_length_m(grouped.fetch('sill_beam', [])),
          :total_concrete_volume_m3 => pieces.sum { |piece| piece.respond_to?(:volume) ? volume_to_m3(piece.volume.to_f) : 0.0 }
        }
      end

      def structural_pieces_for_walls(model, walls)
        groups = Array(walls).flat_map do |wall|
          block_group = WallBlockBuilder.block_group_for_wall(model, wall)
          block_group&.valid? ? [block_group] : []
        end

        room_tokens = Array(walls).map { |wall| GeometryBuilder.room_token(wall).to_s }.reject(&:empty?).uniq
        room_tokens.each do |token|
          junction = WallBlockBuilder.room_junction_group_for_token(model, token)
          groups << junction if junction&.valid?
        end

        scope_keys = Array(walls).map { |wall| wall.get_attribute(PLUGIN_ID, 'conversion_scope_key').to_s }.reject(&:empty?).uniq
        scope_keys.each do |scope_key|
          junction = WallBlockBuilder.cluster_junction_group_for_scope(model, scope_key)
          groups << junction if junction&.valid?
        end

        groups.compact.uniq.flat_map do |group|
          structural_pieces_in_group(group)
        end.uniq(&:persistent_id)
      end

      def structural_pieces_in_group(group)
        return [] unless group&.valid?

        group.entities.each_with_object([]) do |entity, result|
          if entity.is_a?(Sketchup::Group)
            result << entity if entity.get_attribute(PLUGIN_ID, 'entity_type') == 'wall_structural_piece'
            result.concat(structural_pieces_in_group(entity))
          end
        end
      end

      def total_piece_length_m(pieces)
        Array(pieces).sum do |piece|
          piece.get_attribute(PLUGIN_ID, 'length_cm', 0).to_f / 100.0
        end
      end

      def sum_field(entries, key)
        Array(entries).sum { |entry| entry[key].to_f }
      end

      def sum_integer_field(entries, key)
        Array(entries).sum { |entry| entry[key].to_i }
      end

      def empty_structure_estimate
        {
          :column_count => 0,
          :bond_beam_length_m => 0.0,
          :lintel_count => 0,
          :lintel_length_m => 0.0,
          :sill_beam_count => 0,
          :sill_beam_length_m => 0.0,
          :column_volume_m3 => 0.0,
          :bond_beam_volume_m3 => 0.0,
          :lintel_volume_m3 => 0.0,
          :sill_beam_volume_m3 => 0.0,
          :total_concrete_volume_m3 => 0.0,
          :warning_text => ''
        }
      end

      def model_label(model)
        path = model.path.to_s
        return File.basename(path, '.skp') unless path.empty?

        title = model.title.to_s.strip
        return title unless title.empty?

        'modelo_atual'
      end

      def meters(length)
        length.to_f / 1.m.to_f
      end

      def volume_to_m3(volume)
        volume.to_f / (1.m.to_f**3)
      end
    end
  end
end
