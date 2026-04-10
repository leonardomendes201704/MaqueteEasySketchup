module LeonardoLabs
  module PlanForgeBuilder
    module WallBlockBuilder
      extend self

      GROUP_ENTITY_TYPE = 'wall_blocks'.freeze
      MASONRY_GROUP_ENTITY_TYPE = 'wall_block_units'.freeze
      COLUMN_GROUP_ENTITY_TYPE = 'wall_structure_columns'.freeze
      BEAM_GROUP_ENTITY_TYPE = 'wall_structure_beams'.freeze
      ROOM_JUNCTION_GROUP_ENTITY_TYPE = 'room_wall_structure_junctions'.freeze
      CLUSTER_JUNCTION_GROUP_ENTITY_TYPE = 'wall_structure_junctions'.freeze
      UNIT_ENTITY_TYPE = 'wall_block_unit'.freeze
      STRUCTURE_PIECE_ENTITY_TYPE = 'wall_structural_piece'.freeze

      FULL_KIND = 'full'.freeze
      HALF_KIND = 'half'.freeze
      CUT_KIND = 'cut'.freeze

      COLUMN_KIND = 'column'.freeze
      JUNCTION_COLUMN_KIND = 'junction_column'.freeze
      BOND_BEAM_KIND = 'bond_beam'.freeze
      LINTEL_KIND = 'lintel'.freeze
      SILL_BEAM_KIND = 'sill_beam'.freeze

      BLOCK_LENGTH = 39.cm
      HALF_BLOCK_LENGTH = 19.cm
      BLOCK_HEIGHT = 19.cm
      STRUCTURE_DEPTH = 19.cm
      COURSE_HEIGHT = 20.cm
      JOINT_SIZE = 1.cm
      OPENING_SUPPORT = 20.cm
      TOLERANCE = 1.mm

      def wall_blocks_group?(entity)
        entity.is_a?(Sketchup::Group) && entity.get_attribute(PLUGIN_ID, 'entity_type') == GROUP_ENTITY_TYPE
      end

      def room_junction_group?(entity)
        entity.is_a?(Sketchup::Group) && entity.get_attribute(PLUGIN_ID, 'entity_type') == ROOM_JUNCTION_GROUP_ENTITY_TYPE
      end

      def cluster_junction_group?(entity)
        entity.is_a?(Sketchup::Group) && entity.get_attribute(PLUGIN_ID, 'entity_type') == CLUSTER_JUNCTION_GROUP_ENTITY_TYPE
      end

      def wall_block_unit?(entity)
        entity.respond_to?(:get_attribute) && entity.get_attribute(PLUGIN_ID, 'entity_type') == UNIT_ENTITY_TYPE
      end

      def structural_piece?(entity)
        entity.respond_to?(:get_attribute) && entity.get_attribute(PLUGIN_ID, 'entity_type') == STRUCTURE_PIECE_ENTITY_TYPE
      end

      def host_wall_for_entity(model, entity)
        return entity if GeometryBuilder.wall_group?(entity)

        owner = entity
        while owner
          source_id = owner.respond_to?(:get_attribute) ? owner.get_attribute(PLUGIN_ID, 'source_wall_id') : nil
          wall = wall_from_id(model, source_id)
          return wall if wall

          owner = owning_container(owner)
        end

        nil
      end

      def block_group_for_wall(model, wall_group)
        block_groups_for_wall(model, wall_group).max_by(&:persistent_id)
      end

      def block_groups_for_wall(model, wall_group)
        return [] unless model && wall_group&.valid?

        source_id = wall_group.persistent_id
        model.active_entities.grep(Sketchup::Group).select do |group|
          wall_blocks_group?(group) && group.get_attribute(PLUGIN_ID, 'source_wall_id').to_i == source_id
        end
      end

      def room_junction_group_for_token(model, room_token)
        room_junction_groups_for_token(model, room_token).max_by(&:persistent_id)
      end

      def room_junction_groups_for_token(model, room_token)
        token = room_token.to_s
        return [] unless model && !token.empty?

        model.active_entities.grep(Sketchup::Group).select do |group|
          room_junction_group?(group) && GeometryBuilder.room_token(group).to_s == token
        end
      end

      def cluster_junction_group_for_scope(model, scope_key)
        cluster_junction_groups_for_scope(model, scope_key).max_by(&:persistent_id)
      end

      def cluster_junction_groups_for_scope(model, scope_key)
        key = scope_key.to_s
        return [] unless model && !key.empty?

        model.active_entities.grep(Sketchup::Group).select do |group|
          cluster_junction_group?(group) && group.get_attribute(PLUGIN_ID, 'conversion_scope_key').to_s == key
        end
      end

      def conversion_state(model, wall_group)
        block_group = block_group_for_wall(model, wall_group)
        has_conversion = !!block_group || wall_group.get_attribute(PLUGIN_ID, 'has_block_conversion', false)
        warning = if block_group
                    block_group.get_attribute(PLUGIN_ID, 'block_conversion_warning').to_s
                  else
                    wall_group.get_attribute(PLUGIN_ID, 'block_conversion_warning').to_s
                  end

        {
          :has_block_conversion => !!has_conversion,
          :block_conversion_hidden_host => wall_group.hidden?,
          :block_conversion_warning => warning,
          :button_label => has_conversion ? 'Regenerar blocos' : 'Converter em blocos',
          :can_remove_block_conversion => !!has_conversion
        }
      end

      def structure_estimate(wall_group)
        return nil unless GeometryBuilder.physical_wall_group?(wall_group)

        wall = GeometryBuilder.wall_info(wall_group)
        return nil unless wall

        context = structure_context_for_wall(wall_group)
        structure_plan(wall, GeometryBuilder.opening_records(wall_group), context)[:summary]
      end

      def build_for_wall(model, wall_group, settings = nil, replace_existing = true)
        raise ArgumentError, 'Selecione uma parede fisica do PlanForge Builder para converter em blocos.' unless GeometryBuilder.physical_wall_group?(wall_group)

        room_token = GeometryBuilder.room_token(wall_group).to_s
        return build_for_room(model, room_token, settings, replace_existing, wall_group) unless room_token.empty?

        cluster_walls = connected_physical_wall_cluster(model, wall_group)
        if cluster_walls.length > 1
          return build_for_connected_cluster(model, cluster_walls, settings, replace_existing, wall_group)
        end

        remove_for_wall(model, wall_group, true) if replace_existing
        build_isolated_wall(model, wall_group, settings)
      end

      def remove_for_wall(model, wall_group, keep_host_hidden = false)
        return true unless wall_group&.valid?

        room_token = GeometryBuilder.room_token(wall_group).to_s
        if GeometryBuilder.physical_wall_group?(wall_group) && !room_token.empty?
          remove_room_conversion(model, room_token, nil, keep_host_hidden)
          return true
        end

        if GeometryBuilder.physical_wall_group?(wall_group)
          scope_key = wall_group.get_attribute(PLUGIN_ID, 'conversion_scope_key').to_s
          cluster_walls = scope_key.empty? ? connected_physical_wall_cluster(model, wall_group) : cluster_walls_for_scope(model, scope_key)
          if cluster_walls.length > 1 && cluster_conversion_present?(model, cluster_walls)
            remove_connected_cluster_conversion(model, cluster_walls, keep_host_hidden)
            return true
          end
        end

        groups = block_groups_for_wall(model, wall_group).select(&:valid?)
        model.active_entities.erase_entities(groups) unless groups.empty?

        clear_conversion_state(wall_group)
        wall_group.hidden = false if wall_group&.valid? && !keep_host_hidden
        true
      end

      def refresh_for_wall(model, wall_group)
        return nil unless wall_group&.valid?

        if GeometryBuilder.physical_wall_group?(wall_group)
          room_token = GeometryBuilder.room_token(wall_group).to_s
          unless room_token.empty?
            snapshot = RoomRegenerator.room_snapshot(model, room_token)
            walls = room_physical_walls(snapshot[:walls])
            has_conversion = room_conversion_present?(model, room_token, walls)
            return nil unless has_conversion

            return build_for_room(model, room_token, GeometryBuilder.entity_settings(wall_group), true, wall_group)
          end

          cluster_walls = connected_physical_wall_cluster(model, wall_group)
          if cluster_walls.length > 1 && cluster_conversion_present?(model, cluster_walls)
            return build_for_connected_cluster(model, cluster_walls, GeometryBuilder.entity_settings(wall_group), true, wall_group)
          end
        end

        block_group = block_group_for_wall(model, wall_group)
        has_conversion = !!block_group || wall_group.get_attribute(PLUGIN_ID, 'has_block_conversion', false)
        return nil unless has_conversion

        unless GeometryBuilder.physical_wall_group?(wall_group)
          remove_for_wall(model, wall_group)
          return nil
        end

        build_isolated_wall(model, wall_group, GeometryBuilder.entity_settings(wall_group), true)
      end

      def refresh_for_walls(model, walls)
        handled_rooms = {}
        handled_clusters = {}
        Array(walls).uniq.each_with_object([]) do |wall, rebuilt|
          next unless wall&.valid?

          room_token = GeometryBuilder.room_token(wall).to_s
          if GeometryBuilder.physical_wall_group?(wall) && !room_token.empty?
            next if handled_rooms[room_token]

            snapshot = RoomRegenerator.room_snapshot(model, room_token)
            physical_walls = room_physical_walls(snapshot[:walls])
            next unless room_conversion_present?(model, room_token, physical_walls)

            refreshed = build_for_room(model, room_token, GeometryBuilder.entity_settings(wall), true, wall)
            rebuilt << refreshed if refreshed
            handled_rooms[room_token] = true
            next
          end

          if GeometryBuilder.physical_wall_group?(wall)
            cluster_walls = connected_physical_wall_cluster(model, wall)
            if cluster_walls.length > 1
              scope_key = cluster_scope_key(cluster_walls)
              next if handled_clusters[scope_key]
              next unless cluster_conversion_present?(model, cluster_walls)

              refreshed = build_for_connected_cluster(model, cluster_walls, GeometryBuilder.entity_settings(wall), true, wall)
              rebuilt << refreshed if refreshed
              handled_clusters[scope_key] = true
              next
            end
          end

          refreshed = refresh_for_wall(model, wall)
          rebuilt << refreshed if refreshed
        end
      end

      private

      def build_for_room(model, room_token, settings = nil, replace_existing = true, focus_wall = nil)
        snapshot = RoomRegenerator.room_snapshot(model, room_token)
        walls = room_physical_walls(snapshot[:walls])
        raise ArgumentError, 'Nao foi possivel localizar as paredes fisicas do comodo selecionado.' if walls.empty?

        focus_wall = walls.find { |wall| wall == focus_wall } || walls.first
        sanitized = Settings.sanitize(GeometryBuilder.entity_settings(focus_wall).merge(symbolize(settings)))
        remove_room_conversion(model, room_token, walls, true) if replace_existing

        contour = GeometryBuilder.normalized_contour_points(snapshot[:contour])
        shared_plan = shared_junction_plan(room_token, walls, room_token)
        junction_group = build_room_junction_group(model, room_token, contour, sanitized, shared_plan, focus_wall)
        created_groups = []

        walls.each do |wall_group|
          wall = GeometryBuilder.wall_info(wall_group)
          next unless wall

          created_groups << build_wall_group(
            model,
            wall_group,
            wall,
            sanitized,
            room_token,
            contour,
            wall_structure_context(shared_plan, wall_group)
          )
        end

        created_groups.find do |group|
          group.get_attribute(PLUGIN_ID, 'source_wall_id').to_i == focus_wall.persistent_id
        end || junction_group
      rescue StandardError
        cleanup = Array(created_groups).select(&:valid?)
        cleanup << junction_group if junction_group&.valid?
        model.active_entities.erase_entities(cleanup) unless cleanup.empty?
        raise
      end

      def build_for_connected_cluster(model, walls, settings = nil, replace_existing = true, focus_wall = nil)
        cluster_walls = room_physical_walls(walls).select { |wall| GeometryBuilder.room_token(wall).to_s.empty? }.uniq
        raise ArgumentError, 'Nao foi possivel localizar paredes conectadas para a conversao compartilhada.' if cluster_walls.length < 2

        focus_wall = cluster_walls.find { |wall| wall == focus_wall } || cluster_walls.first
        sanitized = Settings.sanitize(GeometryBuilder.entity_settings(focus_wall).merge(symbolize(settings)))
        remove_connected_cluster_conversion(model, cluster_walls, true) if replace_existing
        rebuild_connected_cluster_hosts(cluster_walls)

        scope_key = cluster_scope_key(cluster_walls)
        shared_plan = shared_junction_plan(scope_key, cluster_walls)
        junction_group = build_cluster_junction_group(model, scope_key, sanitized, shared_plan, focus_wall)
        created_groups = []

        cluster_walls.each do |wall_group|
          wall = GeometryBuilder.wall_info(wall_group)
          next unless wall

          context = wall_structure_context(shared_plan, wall_group).merge(:scope_key => scope_key)
          created_groups << build_wall_group(model, wall_group, wall, sanitized, nil, [], context)
        end

        created_groups.find do |group|
          group.get_attribute(PLUGIN_ID, 'source_wall_id').to_i == focus_wall.persistent_id
        end || junction_group
      rescue StandardError
        cleanup = Array(created_groups).select(&:valid?)
        cleanup << junction_group if junction_group&.valid?
        model.active_entities.erase_entities(cleanup) unless cleanup.empty?
        raise
      end

      def build_isolated_wall(model, wall_group, settings = nil, replace_existing = false)
        remove_for_wall(model, wall_group, true) if replace_existing

        wall = GeometryBuilder.wall_info(wall_group)
        raise ArgumentError, 'Nao foi possivel ler a geometria da parede selecionada.' unless wall

        sanitized = Settings.sanitize(GeometryBuilder.entity_settings(wall_group).merge(symbolize(settings)))
        room_token = GeometryBuilder.room_token(wall_group)
        contour = GeometryBuilder.room_contour(wall_group)
        build_wall_group(model, wall_group, wall, sanitized, room_token, contour, {})
      end

      def build_wall_group(model, wall_group, wall, settings, room_token, contour, structure_context)
        parent = model.active_entities.add_group
        parent.name = 'PlanForge Wall Blocks'
        tag_generated_entity(parent, wall_group, GROUP_ENTITY_TYPE)
        scope_key = structure_context[:scope_key].to_s
        parent.set_attribute(PLUGIN_ID, 'conversion_scope_key', scope_key) unless scope_key.empty?

        if !room_token.to_s.empty? && !Array(contour).empty?
          GeometryBuilder.tag_room_entity(parent, contour, settings, room_token)
        elsif !room_token.to_s.empty?
          parent.set_attribute(PLUGIN_ID, 'room_token', room_token)
        end
        parent.set_attribute(PLUGIN_ID, 'source_room_token', room_token.to_s) unless room_token.to_s.empty?

        summary = build_conversion(parent, wall_group, wall, settings, room_token, structure_context)
        warning = block_conversion_warning(wall_group, summary)

        parent.set_attribute(PLUGIN_ID, 'course_count', summary[:course_count])
        parent.set_attribute(PLUGIN_ID, 'piece_count', summary[:piece_count])
        parent.set_attribute(PLUGIN_ID, 'cut_piece_count', summary[:cut_piece_count])
        parent.set_attribute(PLUGIN_ID, 'column_count', summary[:column_count])
        parent.set_attribute(PLUGIN_ID, 'bond_beam_length_m', summary[:bond_beam_length_m])
        parent.set_attribute(PLUGIN_ID, 'lintel_count', summary[:lintel_count])
        parent.set_attribute(PLUGIN_ID, 'lintel_length_m', summary[:lintel_length_m])
        parent.set_attribute(PLUGIN_ID, 'sill_beam_count', summary[:sill_beam_count])
        parent.set_attribute(PLUGIN_ID, 'sill_beam_length_m', summary[:sill_beam_length_m])
        parent.set_attribute(PLUGIN_ID, 'total_concrete_volume_m3', summary[:total_concrete_volume_m3])
        set_optional_attribute(parent, 'structure_warning', summary[:warning_text])
        set_optional_attribute(parent, 'block_conversion_warning', warning)

        LayerManager.apply_to_entity(parent, :wall)
        MaterialManager.apply_to_entity(parent, :wall, settings)
        paint_generated_entities(parent, settings)

        wall_group.hidden = true
        wall_group.set_attribute(PLUGIN_ID, 'has_block_conversion', true)
        wall_group.set_attribute(PLUGIN_ID, 'block_group_id', parent.persistent_id)
        wall_group.set_attribute(PLUGIN_ID, 'conversion_scope_key', scope_key) unless scope_key.empty?
        set_optional_attribute(wall_group, 'block_conversion_warning', warning)

        parent
      rescue StandardError
        model.active_entities.erase_entities(parent) if parent&.valid?
        raise
      end

      def build_conversion(parent, wall_group, wall, settings, room_token, structure_context = {})
        openings = GeometryBuilder.opening_records(wall_group)
        structure = structure_plan(wall, openings, structure_context)
        build_structure(parent, wall_group, wall, structure[:pieces], room_token)
        masonry_group = create_container_group(parent, wall_group, 'PlanForge Wall Masonry', MASONRY_GROUP_ENTITY_TYPE, room_token)
        masonry_summary = build_courses(masonry_group, wall_group, wall, settings, structure[:opening_profiles], structure[:pieces])
        masonry_summary.merge(structure[:summary])
      end

      def build_room_junction_group(model, room_token, contour, settings, shared_plan, focus_wall)
        nodes = Array(shared_plan[:nodes])
        return nil if nodes.empty?

        group = model.active_entities.add_group
        group.name = 'PlanForge Room Junction Columns'
        group.set_attribute(PLUGIN_ID, 'entity_type', ROOM_JUNCTION_GROUP_ENTITY_TYPE)
        group.set_attribute(PLUGIN_ID, 'primary_wall_id', focus_wall.persistent_id) if focus_wall&.valid?
        group.set_attribute(PLUGIN_ID, 'source_wall_id', focus_wall.persistent_id) if focus_wall&.valid?
        group.set_attribute(PLUGIN_ID, 'source_room_token', room_token.to_s) unless room_token.to_s.empty?

        if !Array(contour).empty?
          GeometryBuilder.tag_room_entity(group, contour, settings, room_token)
        else
          group.set_attribute(PLUGIN_ID, 'room_token', room_token)
        end

        nodes.each do |node|
          create_junction_column_piece(group, node)
        end

        group.set_attribute(PLUGIN_ID, 'junction_count', nodes.length)
        LayerManager.apply_to_entity(group, :wall)
        MaterialManager.apply_to_entity(group, :wall, settings)
        paint_generated_entities(group, settings)
        group
      rescue StandardError
        model.active_entities.erase_entities(group) if group&.valid?
        raise
      end

      def build_cluster_junction_group(model, scope_key, settings, shared_plan, focus_wall)
        nodes = Array(shared_plan[:nodes])
        return nil if nodes.empty?

        group = model.active_entities.add_group
        group.name = 'PlanForge Junction Columns'
        group.set_attribute(PLUGIN_ID, 'entity_type', CLUSTER_JUNCTION_GROUP_ENTITY_TYPE)
        group.set_attribute(PLUGIN_ID, 'primary_wall_id', focus_wall.persistent_id) if focus_wall&.valid?
        group.set_attribute(PLUGIN_ID, 'source_wall_id', focus_wall.persistent_id) if focus_wall&.valid?
        group.set_attribute(PLUGIN_ID, 'conversion_scope_key', scope_key.to_s)

        nodes.each do |node|
          create_junction_column_piece(group, node)
        end

        group.set_attribute(PLUGIN_ID, 'junction_count', nodes.length)
        LayerManager.apply_to_entity(group, :wall)
        MaterialManager.apply_to_entity(group, :wall, settings)
        paint_generated_entities(group, settings)
        group
      rescue StandardError
        model.active_entities.erase_entities(group) if group&.valid?
        raise
      end

      def create_container_group(parent, wall_group, name, entity_type, room_token)
        group = parent.entities.add_group
        group.name = name
        tag_generated_entity(group, wall_group, entity_type, room_token)
        group
      end

      def build_courses(parent, wall_group, wall, settings, opening_profiles, structure_pieces)
        piece_count = 0
        cut_piece_count = 0
        course_count = 0

        course_spans(wall).each do |course|
          course_count += 1
          blockers = course_blockers_for_course(opening_profiles, structure_pieces, course[:bottom_z], course[:top_z])
          course_pattern_pieces(wall[:length], course[:index]).each do |piece|
            subtract_intervals(piece_interval(piece), blockers).each do |segment|
              next if segment_length(segment) <= TOLERANCE

              kind = segment_kind(piece, segment, course[:height])
              create_block_piece(parent, wall_group, wall, settings, course, piece[:bond_offset], segment, kind)
              piece_count += 1
              cut_piece_count += 1 if kind == CUT_KIND
            end
          end
        end

        {
          :course_count => course_count,
          :piece_count => piece_count,
          :cut_piece_count => cut_piece_count
        }
      end

      def build_structure(parent, wall_group, wall, pieces, room_token)
        columns_group = nil
        beams_group = nil

        Array(pieces).each do |piece|
          next if piece[:emit] == false

          if piece[:kind] == COLUMN_KIND
            columns_group ||= create_container_group(parent, wall_group, 'PlanForge Wall Columns', COLUMN_GROUP_ENTITY_TYPE, room_token)
            target = columns_group
          else
            beams_group ||= create_container_group(parent, wall_group, 'PlanForge Wall Beams', BEAM_GROUP_ENTITY_TYPE, room_token)
            target = beams_group
          end
          create_structure_piece(target, wall_group, wall, piece)
        end
      end

      def structure_plan(wall, openings, options = {})
        structure_depth = [STRUCTURE_DEPTH, wall[:height].to_f].min
        return empty_structure_summary if structure_depth <= TOLERANCE

        wall_top = wall[:base_z].to_f + wall[:height].to_f
        labels = opening_labels(openings)
        warnings = Array(options[:warnings]).map(&:to_s).reject(&:empty?)
        pieces = []
        opening_profiles = []

        column_layout = structure_column_layout(wall, structure_depth, wall_top, options)
        pieces.concat(column_layout[:pieces])

        left_inner = column_layout[:left_inner]
        right_inner = column_layout[:right_inner]
        bond_beam = nil
        bond_beam_bottom = modular_bond_beam_bottom(wall, structure_depth)
        if (right_inner - left_inner) > TOLERANCE && (wall_top - bond_beam_bottom) > TOLERANCE
          bond_beam = structure_piece_payload(
            BOND_BEAM_KIND,
            left_inner,
            right_inner,
            bond_beam_bottom,
            wall_top,
            wall[:thickness]
          )
          pieces << bond_beam
        end

        Array(openings).each do |opening|
          profile = opening_profile(opening, wall, left_inner, right_inner, bond_beam, structure_depth, labels)
          pieces.concat(profile[:pieces])
          warnings.concat(profile[:warnings])
          opening_profiles << profile[:opening_blocker]
        end

        summary = structure_summary_from_pieces(pieces, warnings)
        {
          :pieces => pieces.sort_by { |piece| [piece[:bottom_z].to_f, piece[:start].to_f, piece[:kind].to_s] },
          :opening_profiles => opening_profiles,
          :summary => summary
        }
      end

      def structure_column_layout(wall, structure_depth, wall_top, options = {})
        pieces = []
        local_ranges = column_intervals(wall[:length].to_f, structure_depth)
        start_piece = endpoint_column_piece(
          wall,
          wall_top,
          options[:start_column],
          local_ranges.first,
          'start_column'
        )
        end_piece = endpoint_column_piece(
          wall,
          wall_top,
          options[:end_column],
          local_ranges.last,
          'end_column'
        )

        pieces << start_piece if start_piece
        pieces << end_piece if end_piece

        {
          :pieces => pieces,
          :left_inner => start_piece ? start_piece[:end].to_f : 0.0,
          :right_inner => end_piece ? end_piece[:start].to_f : wall[:length].to_f
        }
      end

      def endpoint_column_piece(wall, wall_top, override, fallback_range, piece_id)
        piece_range = override && override[:range] ? override[:range] : fallback_range
        return nil if piece_range.nil? || segment_length(piece_range) <= TOLERANCE

        emit = override ? false : true
        piece = structure_piece_payload(
          COLUMN_KIND,
          piece_range[0],
          piece_range[1],
          wall[:base_z],
          wall_top,
          wall[:thickness],
          nil,
          override && override[:junction_id] ? override[:junction_id] : piece_id,
          :emit => emit
        )

        if override
          piece[:junction_id] = override[:junction_id].to_s
          piece[:junction_kind] = override[:junction_kind].to_s
          piece[:connected_wall_ids] = Array(override[:connected_wall_ids]).map(&:to_i)
          piece[:primary_wall_id] = override[:primary_wall_id].to_i
        end

        piece
      end

      def opening_profile(opening, wall, left_inner, right_inner, bond_beam, structure_depth, labels)
        support_range = supported_opening_range(opening, left_inner, right_inner)
        label = labels[opening[:id].to_s] || opening_type_label(opening[:kind])
        opening_blocker = opening.dup
        pieces = []
        warnings = []

        lintel = lintel_piece_for_opening(opening, support_range, wall, structure_depth, bond_beam, wall[:thickness])
        warnings << "#{label}: #{lintel[:warning]}" if lintel[:warning]
        pieces << lintel[:piece] if lintel[:piece]
        opening_blocker[:top_z] = lintel[:blocker_top_z].to_f if lintel[:blocker_top_z]
        warnings << "#{label}: topo ajustado a modulacao da fiada na conversao em blocos." if lintel[:adjusted]

        if opening[:kind].to_s == 'window'
          sill = sill_piece_for_opening(opening, support_range, wall[:base_z], structure_depth, wall[:thickness])
          warnings << "#{label}: #{sill[:warning]}" if sill[:warning]
          pieces << sill[:piece] if sill[:piece]
          opening_blocker[:bottom_z] = sill[:blocker_bottom_z].to_f if sill[:blocker_bottom_z]
          warnings << "#{label}: peitoril ajustado a modulacao da fiada na conversao em blocos." if sill[:adjusted]
        end

        {
          :opening_blocker => opening_blocker,
          :pieces => pieces,
          :warnings => warnings
        }
      end

      def lintel_piece_for_opening(opening, support_range, wall, structure_depth, bond_beam, wall_thickness)
        if segment_length(support_range) <= TOLERANCE
          return { :warning => 'verga omitida por falta de apoio entre colunas.', :adjusted => false, :blocker_top_z => opening[:top_z].to_f }
        end

        wall_top = wall[:base_z].to_f + wall[:height].to_f
        lintel_bottom = modular_lintel_bottom(wall, opening[:top_z])
        lintel_top = [lintel_bottom + structure_depth, wall_top].min
        if bond_beam && lintel_top >= (bond_beam[:bottom_z].to_f - TOLERANCE)
          return {
            :warning => 'verga absorvida pela cinta superior.',
            :piece => nil,
            :adjusted => (bond_beam[:bottom_z].to_f - opening[:top_z].to_f).abs > TOLERANCE,
            :blocker_top_z => bond_beam[:bottom_z].to_f
          }
        end

        {
          :piece => structure_piece_payload(
            LINTEL_KIND,
            support_range[0],
            support_range[1],
            lintel_bottom,
            lintel_top,
            wall_thickness,
            opening[:id]
          ),
          :adjusted => (lintel_bottom - opening[:top_z].to_f).abs > TOLERANCE,
          :blocker_top_z => lintel_bottom
        }
      end

      def sill_piece_for_opening(opening, support_range, base_z, structure_depth, wall_thickness)
        if segment_length(support_range) <= TOLERANCE
          return { :warning => 'contra-verga omitida por falta de apoio entre colunas.', :adjusted => false, :blocker_bottom_z => opening[:bottom_z].to_f }
        end

        sill_top = modular_sill_top(base_z, opening[:bottom_z])
        sill_bottom = sill_top - structure_depth
        if sill_bottom <= (base_z.to_f + TOLERANCE)
          return { :warning => 'contra-verga omitida por falta de espaco abaixo do peitoril.', :adjusted => false, :blocker_bottom_z => opening[:bottom_z].to_f }
        end

        {
          :piece => structure_piece_payload(
            SILL_BEAM_KIND,
            support_range[0],
            support_range[1],
            sill_bottom,
            sill_top,
            wall_thickness,
            opening[:id]
          ),
          :adjusted => (sill_top - opening[:bottom_z].to_f).abs > TOLERANCE,
          :blocker_bottom_z => sill_top
        }
      end

      def structure_piece_payload(kind, start_pos, end_pos, bottom_z, top_z, thickness, opening_id = nil, piece_id = nil, extra = {})
        {
          :id => piece_id || "#{kind}_#{opening_id}_#{format('%.2f', start_pos)}_#{format('%.2f', bottom_z)}",
          :kind => kind,
          :start => start_pos.to_f,
          :end => end_pos.to_f,
          :bottom_z => bottom_z.to_f,
          :top_z => top_z.to_f,
          :thickness => thickness.to_f,
          :source_opening_id => opening_id.to_s,
          :emit => extra.key?(:emit) ? extra[:emit] : true
        }.merge(extra.reject { |key, _value| key == :emit })
      end

      def supported_opening_range(opening, left_inner, right_inner)
        [
          [opening_left(opening) - OPENING_SUPPORT, left_inner].max,
          [opening_right(opening) + OPENING_SUPPORT, right_inner].min
        ]
      end

      def opening_left(opening)
        opening[:center_distance].to_f - (opening[:opening_width].to_f / 2.0)
      end

      def opening_right(opening)
        opening[:center_distance].to_f + (opening[:opening_width].to_f / 2.0)
      end

      def column_intervals(total_length, column_length)
        return [[0.0, total_length.to_f], [total_length.to_f, total_length.to_f]] if total_length <= (column_length + TOLERANCE)

        if total_length <= ((column_length * 2.0) + TOLERANCE)
          midpoint = total_length / 2.0
          [[0.0, midpoint], [midpoint, total_length.to_f]]
        else
          [[0.0, column_length], [total_length - column_length, total_length.to_f]]
        end
      end

      def structure_summary_from_pieces(pieces, warnings)
        grouped = Array(pieces).group_by { |piece| piece[:kind].to_s }
        summary = {
          :column_count => grouped.fetch(COLUMN_KIND, []).length,
          :bond_beam_length_m => total_piece_length_m(grouped.fetch(BOND_BEAM_KIND, [])),
          :lintel_count => grouped.fetch(LINTEL_KIND, []).length,
          :lintel_length_m => total_piece_length_m(grouped.fetch(LINTEL_KIND, [])),
          :sill_beam_count => grouped.fetch(SILL_BEAM_KIND, []).length,
          :sill_beam_length_m => total_piece_length_m(grouped.fetch(SILL_BEAM_KIND, [])),
          :column_volume_m3 => total_piece_volume_m3(grouped.fetch(COLUMN_KIND, [])),
          :bond_beam_volume_m3 => total_piece_volume_m3(grouped.fetch(BOND_BEAM_KIND, [])),
          :lintel_volume_m3 => total_piece_volume_m3(grouped.fetch(LINTEL_KIND, [])),
          :sill_beam_volume_m3 => total_piece_volume_m3(grouped.fetch(SILL_BEAM_KIND, []))
        }
        summary[:total_concrete_volume_m3] = [
          summary[:column_volume_m3],
          summary[:bond_beam_volume_m3],
          summary[:lintel_volume_m3],
          summary[:sill_beam_volume_m3]
        ].sum
        summary[:warnings] = Array(warnings).map(&:to_s).reject(&:empty?).uniq
        summary[:warning_text] = summary[:warnings].join(' | ')
        summary
      end

      def empty_structure_summary
        {
          :pieces => [],
          :opening_profiles => [],
          :summary => {
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
            :warnings => [],
            :warning_text => ''
          }
        }
      end

      def total_piece_length_m(pieces)
        Array(pieces).sum { |piece| segment_length([piece[:start], piece[:end]]) / 1.m.to_f }
      end

      def total_piece_volume_m3(pieces)
        Array(pieces).sum do |piece|
          piece_length = segment_length([piece[:start], piece[:end]])
          piece_height = piece[:top_z].to_f - piece[:bottom_z].to_f
          (piece_length * piece_height * piece[:thickness].to_f) / (1.m.to_f**3)
        end
      end

      def opening_labels(openings)
        counts = Hash.new(0)
        Array(openings).each_with_object({}) do |opening, result|
          label_root = opening_type_label(opening[:kind])
          counts[label_root] += 1
          result[opening[:id].to_s] = "#{label_root} #{counts[label_root]}"
        end
      end

      def opening_type_label(kind)
        kind.to_s == 'window' ? 'Janela' : 'Porta'
      end

      def course_spans(wall)
        spans = []
        top_z = wall[:base_z] + wall[:height]
        index = 0
        current_bottom = wall[:base_z]

        while current_bottom < (top_z - TOLERANCE)
          remaining = top_z - current_bottom
          height = [BLOCK_HEIGHT, remaining].min
          spans << {
            :index => index,
            :bottom_z => current_bottom,
            :top_z => current_bottom + height,
            :height => height
          }
          index += 1
          current_bottom += COURSE_HEIGHT
        end

        spans
      end

      def course_pattern_pieces(total_length, course_index)
        pieces = []
        cursor = 0.0
        offset = (course_index % 2).zero? ? 0.0 : (HALF_BLOCK_LENGTH + JOINT_SIZE)
        first_module = !(course_index % 2).zero?

        while cursor < (total_length - TOLERANCE)
          module_length = first_module ? (HALF_BLOCK_LENGTH + JOINT_SIZE) : (BLOCK_LENGTH + JOINT_SIZE)
          standard_length = first_module ? HALF_BLOCK_LENGTH : BLOCK_LENGTH
          standard_kind = first_module ? HALF_KIND : FULL_KIND
          remaining = total_length - cursor
          piece_end = remaining <= (module_length + TOLERANCE) ? total_length : (cursor + standard_length)
          piece_length = piece_end - cursor
          kind = (piece_length - standard_length).abs <= TOLERANCE ? standard_kind : CUT_KIND

          pieces << {
            :start => cursor,
            :end => piece_end,
            :kind => kind,
            :bond_offset => offset
          }

          cursor += module_length
          first_module = false
        end

        pieces
      end

      def piece_interval(piece)
        [piece[:start].to_f, piece[:end].to_f]
      end

      def course_blockers_for_course(openings, structure_pieces, bottom_z, top_z)
        merged_intervals(
          opening_blockers_for_course(openings, bottom_z, top_z) +
          structure_blockers_for_course(structure_pieces, bottom_z, top_z)
        )
      end

      def opening_blockers_for_course(opening_profiles, bottom_z, top_z)
        Array(opening_profiles).each_with_object([]) do |opening, result|
          next unless opening[:bottom_z].to_f < (top_z - TOLERANCE)
          next unless opening[:top_z].to_f > (bottom_z + TOLERANCE)

          result << [opening_left(opening), opening_right(opening)]
        end
      end

      def structure_blockers_for_course(pieces, bottom_z, top_z)
        Array(pieces).each_with_object([]) do |piece, result|
          next unless piece[:bottom_z].to_f < (top_z - TOLERANCE)
          next unless piece[:top_z].to_f > (bottom_z + TOLERANCE)

          result << [piece[:start].to_f, piece[:end].to_f]
        end
      end

      def merged_intervals(intervals)
        sorted = Array(intervals).map do |interval|
          [interval[0].to_f, interval[1].to_f]
        end.sort_by(&:first)

        sorted.each_with_object([]) do |interval, result|
          if result.empty? || interval[0] > (result.last[1] + TOLERANCE)
            result << interval
          else
            result.last[1] = [result.last[1], interval[1]].max
          end
        end
      end

      def subtract_intervals(base_interval, blockers)
        segments = [base_interval]

        Array(blockers).each do |blocker|
          segments = segments.flat_map do |segment|
            subtract_interval(segment, blocker)
          end
        end

        segments.select { |segment| segment_length(segment) > TOLERANCE }
      end

      def subtract_interval(segment, blocker)
        start_pos = segment[0]
        end_pos = segment[1]
        blocker_start = blocker[0]
        blocker_end = blocker[1]

        return [segment] if blocker_end <= (start_pos + TOLERANCE) || blocker_start >= (end_pos - TOLERANCE)

        parts = []
        parts << [start_pos, [blocker_start, end_pos].min] if blocker_start > (start_pos + TOLERANCE)
        parts << [[blocker_end, start_pos].max, end_pos] if blocker_end < (end_pos - TOLERANCE)
        parts
      end

      def segment_kind(piece, segment, height)
        return CUT_KIND if (height - BLOCK_HEIGHT).abs > TOLERANCE
        return CUT_KIND if (segment[0] - piece[:start]).abs > TOLERANCE
        return CUT_KIND if (segment[1] - piece[:end]).abs > TOLERANCE

        piece[:kind]
      end

      def create_block_piece(parent, wall_group, wall, settings, course, bond_offset, segment, kind)
        piece_length = segment_length(segment)
        room_token = GeometryBuilder.room_token(wall_group).to_s
        origin = piece_origin(wall, segment[0], course[:bottom_z])
        transformation = Geom::Transformation.axes(origin, wall[:axis], reverse_vector(wall[:left_axis]), Z_AXIS)

        entity = if reusable_piece?(kind, piece_length, course[:height])
                   definition = ensure_definition(parent.model, kind, piece_length, wall[:thickness])
                   parent.entities.add_instance(definition, transformation)
                 else
                   cut_group = parent.entities.add_group
                   build_prism(cut_group.entities, piece_length, wall[:thickness], course[:height])
                   cut_group.move!(transformation)
                   cut_group
                 end

        entity.name = "PlanForge #{kind.capitalize} Block" if entity.respond_to?(:name=)
        entity.set_attribute(PLUGIN_ID, 'entity_type', UNIT_ENTITY_TYPE)
        entity.set_attribute(PLUGIN_ID, 'source_wall_id', wall_group.persistent_id)
        entity.set_attribute(PLUGIN_ID, 'source_room_token', room_token) unless room_token.empty?
        entity.set_attribute(PLUGIN_ID, 'course_index', course[:index])
        entity.set_attribute(PLUGIN_ID, 'piece_kind', kind)
        entity.set_attribute(PLUGIN_ID, 'piece_length_cm', to_cm(piece_length).round(2))
        entity.set_attribute(PLUGIN_ID, 'bond_offset_cm', to_cm(bond_offset).round(2))
        entity.set_attribute(PLUGIN_ID, 'piece_start_cm', to_cm(segment[0]).round(2))
        entity.set_attribute(PLUGIN_ID, 'piece_end_cm', to_cm(segment[1]).round(2))
        entity
      end

      def create_structure_piece(parent, wall_group, wall, piece)
        piece_length = segment_length([piece[:start], piece[:end]])
        piece_height = piece[:top_z].to_f - piece[:bottom_z].to_f
        return nil if piece_length <= TOLERANCE || piece_height <= TOLERANCE

        group = parent.entities.add_group
        build_prism(group.entities, piece_length, wall[:thickness], piece_height)
        group.move!(Geom::Transformation.axes(
          piece_origin(wall, piece[:start], piece[:bottom_z]),
          wall[:axis],
          reverse_vector(wall[:left_axis]),
          Z_AXIS
        ))
        group.name = structure_piece_name(piece[:kind])
        group.set_attribute(PLUGIN_ID, 'entity_type', STRUCTURE_PIECE_ENTITY_TYPE)
        group.set_attribute(PLUGIN_ID, 'source_wall_id', wall_group.persistent_id)
        room_token = GeometryBuilder.room_token(wall_group).to_s
        group.set_attribute(PLUGIN_ID, 'source_room_token', room_token) unless room_token.empty?
        group.set_attribute(PLUGIN_ID, 'structural_kind', piece[:kind].to_s)
        set_optional_attribute(group, 'source_opening_id', piece[:source_opening_id])
        group.set_attribute(PLUGIN_ID, 'length_cm', to_cm(piece_length).round(2))
        group.set_attribute(PLUGIN_ID, 'height_cm', to_cm(piece_height).round(2))
        group.set_attribute(PLUGIN_ID, 'section_thickness_cm', to_cm(wall[:thickness]).round(2))
        group.set_attribute(PLUGIN_ID, 'section_depth_cm', to_cm([piece_length, piece_height].min).round(2))
        group.set_attribute(PLUGIN_ID, 'piece_start_cm', to_cm(piece[:start]).round(2))
        group.set_attribute(PLUGIN_ID, 'piece_end_cm', to_cm(piece[:end]).round(2))
        group
      end

      def create_junction_column_piece(parent, node)
        return nil unless node[:height].to_f > TOLERANCE

        group = parent.entities.add_group
        group.name = structure_piece_name(JUNCTION_COLUMN_KIND)
        footprint = Array(node[:footprint_points])
        face = add_junction_stub_face(group.entities, footprint, node[:base_z])
        raise ArgumentError, 'Nao foi possivel criar a base da coluna compartilhada.' unless face

        face.reverse! if face.normal.z < 0
        face.pushpull(node[:height].to_f)

        group.set_attribute(PLUGIN_ID, 'entity_type', STRUCTURE_PIECE_ENTITY_TYPE)
        group.set_attribute(PLUGIN_ID, 'source_wall_id', node[:primary_wall_id].to_i)
        room_token = node[:room_token].to_s
        group.set_attribute(PLUGIN_ID, 'source_room_token', room_token) unless room_token.empty?
        scope_key = node[:scope_key].to_s
        group.set_attribute(PLUGIN_ID, 'conversion_scope_key', scope_key) unless scope_key.empty?
        group.set_attribute(PLUGIN_ID, 'structural_kind', JUNCTION_COLUMN_KIND)
        group.set_attribute(PLUGIN_ID, 'junction_id', node[:id].to_s)
        group.set_attribute(PLUGIN_ID, 'junction_kind', node[:kind].to_s)
        group.set_attribute(PLUGIN_ID, 'primary_wall_id', node[:primary_wall_id].to_i)
        group.set_attribute(PLUGIN_ID, 'connected_wall_ids', JSON.generate(node[:connected_wall_ids]))
        group.set_attribute(PLUGIN_ID, 'height_cm', to_cm(node[:height]).round(2))
        group.set_attribute(PLUGIN_ID, 'section_thickness_cm', to_cm(node[:max_thickness]).round(2))
        group.set_attribute(PLUGIN_ID, 'section_depth_cm', to_cm(node[:footprint_depth] || STRUCTURE_DEPTH).round(2))
        group
      end

      def add_junction_stub_face(entities, points, base_z)
        face_points = Array(points).map do |point|
          Geom::Point3d.new(point.x, point.y, base_z.to_f)
        end
        entities.add_face(face_points)
      rescue StandardError
        nil
      end

      def structure_piece_name(kind)
        case kind.to_s
        when COLUMN_KIND
          'PlanForge Column'
        when JUNCTION_COLUMN_KIND
          'PlanForge Junction Column'
        when BOND_BEAM_KIND
          'PlanForge Bond Beam'
        when LINTEL_KIND
          'PlanForge Lintel'
        when SILL_BEAM_KIND
          'PlanForge Sill Beam'
        else
          'PlanForge Structural Piece'
        end
      end

      def reusable_piece?(kind, length, height)
        return false unless (height - BLOCK_HEIGHT).abs <= TOLERANCE

        (kind == FULL_KIND && (length - BLOCK_LENGTH).abs <= TOLERANCE) ||
          (kind == HALF_KIND && (length - HALF_BLOCK_LENGTH).abs <= TOLERANCE)
      end

      def ensure_definition(model, kind, length, thickness)
        key = definition_name(kind, length, thickness)
        definition = model.definitions[key]
        return definition if definition

        definition = model.definitions.add(key)
        build_prism(definition.entities, length, thickness, BLOCK_HEIGHT)
        definition
      end

      def build_prism(entities, length, thickness, height)
        face = entities.add_face(
          Geom::Point3d.new(0, 0, 0),
          Geom::Point3d.new(length, 0, 0),
          Geom::Point3d.new(length, thickness, 0),
          Geom::Point3d.new(0, thickness, 0)
        )
        raise ArgumentError, 'Nao foi possivel criar um elemento da alvenaria.' unless face

        face.reverse! if face.normal.z < 0
        face.pushpull(height)
      end

      def piece_origin(wall, start_distance, bottom_z)
        origin = offset_point(wall[:start_point], wall[:left_axis], wall[:left_extent])
        origin = offset_point(origin, wall[:axis], start_distance)
        origin.z = bottom_z
        origin
      end

      def reverse_vector(vector)
        Geom::Vector3d.new(-vector.x, -vector.y, -vector.z)
      end

      def offset_point(point, vector, distance)
        Geom::Point3d.new(
          point.x + (vector.x * distance),
          point.y + (vector.y * distance),
          point.z + (vector.z * distance)
        )
      end

      def paint_generated_entities(group, settings)
        return unless settings[:apply_materials_on_create]

        material = MaterialManager.ensure_material(group.model, :wall, settings)
        apply_material_to_descendants(group.entities, material)
      end

      def apply_material_to_descendants(entities, material)
        entities.each do |entity|
          next unless entity.respond_to?(:material=)

          entity.material = material
          apply_material_to_descendants(entity.entities, material) if entity.is_a?(Sketchup::Group)
        end
      end

      def block_conversion_warning(wall_group, summary)
        warnings = []
        quantity_warning = GeometryBuilder.wall_quantities(wall_group).to_h[:block_warning].to_s
        warnings << quantity_warning unless quantity_warning.empty?
        warnings.concat(Array(summary[:warnings]))
        warnings << 'Algumas fiadas usam blocos cortados para fechar o modulo e contornar aberturas.' if summary[:cut_piece_count].to_i > 0
        warnings.uniq.join(' | ')
      end

      def clear_conversion_state(wall_group)
        return unless wall_group&.valid?

        wall_group.delete_attribute(PLUGIN_ID, 'has_block_conversion')
        wall_group.delete_attribute(PLUGIN_ID, 'block_group_id')
        wall_group.delete_attribute(PLUGIN_ID, 'block_conversion_warning')
        wall_group.delete_attribute(PLUGIN_ID, 'conversion_scope_key')
      end

      def tag_generated_entity(entity, wall_group, entity_type, room_token = nil)
        entity.set_attribute(PLUGIN_ID, 'entity_type', entity_type)
        entity.set_attribute(PLUGIN_ID, 'source_wall_id', wall_group.persistent_id)
        token = room_token.to_s
        token = GeometryBuilder.room_token(wall_group).to_s if token.empty?
        entity.set_attribute(PLUGIN_ID, 'source_room_token', token) unless token.empty?
        entity
      end

      def set_optional_attribute(entity, key, value)
        if value.to_s.strip.empty?
          entity.delete_attribute(PLUGIN_ID, key)
        else
          entity.set_attribute(PLUGIN_ID, key, value)
        end
      end

      def segment_length(segment)
        segment[1].to_f - segment[0].to_f
      end

      def owning_container(entity)
        return nil unless entity.respond_to?(:parent)

        parent = entity.parent
        return nil unless parent.respond_to?(:parent)

        container = parent.parent
        container if container.respond_to?(:get_attribute)
      end

      def wall_from_id(model, source_id)
        identifier = source_id.to_i
        return nil if identifier <= 0

        if model.respond_to?(:find_entity_by_persistent_id)
          entity = model.find_entity_by_persistent_id(identifier)
          return entity if GeometryBuilder.wall_group?(entity)
        end

        model.active_entities.grep(Sketchup::Group).find do |group|
          GeometryBuilder.wall_group?(group) && group.persistent_id == identifier
        end
      end

      def definition_name(kind, length, thickness)
        "PlanForge Block #{kind} #{format('%.2f', to_cm(length))}x#{format('%.2f', to_cm(thickness))}"
      end

      def modular_lintel_bottom(wall, opening_top_z)
        snapped = snapped_course_bottom(wall[:base_z], opening_top_z)
        [wall[:base_z].to_f, snapped].max
      end

      def modular_bond_beam_bottom(wall, structure_depth)
        desired_bottom = (wall[:base_z].to_f + wall[:height].to_f) - structure_depth.to_f
        snapped = snapped_course_bottom(wall[:base_z], desired_bottom)
        [wall[:base_z].to_f, snapped].max
      end

      def modular_sill_top(base_z, opening_bottom_z)
        snapped_course_top(base_z, opening_bottom_z)
      end

      def snapped_course_bottom(base_z, z_value)
        index = ((z_value.to_f - base_z.to_f) / COURSE_HEIGHT.to_f).round
        base_z.to_f + (index * COURSE_HEIGHT.to_f)
      end

      def snapped_course_top(base_z, z_value)
        index = ((z_value.to_f - base_z.to_f - BLOCK_HEIGHT.to_f) / COURSE_HEIGHT.to_f).round
        base_z.to_f + (index * COURSE_HEIGHT.to_f) + BLOCK_HEIGHT.to_f
      end

      def structure_context_for_wall(wall_group)
        room_token = GeometryBuilder.room_token(wall_group).to_s
        unless room_token.empty?
          snapshot = RoomRegenerator.room_snapshot(wall_group.model, room_token)
          physical_walls = room_physical_walls(snapshot[:walls])
          return {} if physical_walls.empty?

          shared_plan = shared_junction_plan(room_token, physical_walls, room_token)
          return wall_structure_context(shared_plan, wall_group)
        end

        cluster_walls = connected_physical_wall_cluster(wall_group.model, wall_group)
        return {} unless cluster_walls.length > 1

        shared_plan = shared_junction_plan(cluster_scope_key(cluster_walls), cluster_walls)
        wall_structure_context(shared_plan, wall_group)
      end

      def wall_structure_context(shared_plan, wall_group)
        overrides = shared_plan[:overrides].fetch(wall_group.persistent_id, {})
        {
          :start_column => overrides[:start_column],
          :end_column => overrides[:end_column]
        }
      end

      def shared_junction_plan(scope_key, wall_groups, room_token = nil)
        endpoint_records = []

        room_physical_walls(wall_groups).each do |wall_group|
          wall = GeometryBuilder.wall_info(wall_group)
          next unless wall

          endpoint_records << {
            :wall_group => wall_group,
            :wall_id => wall_group.persistent_id,
            :wall => wall,
            :endpoint => :start,
            :point => wall[:start_point]
          }
          endpoint_records << {
            :wall_group => wall_group,
            :wall_id => wall_group.persistent_id,
            :wall => wall,
            :endpoint => :end,
            :point => wall[:end_point]
          }
        end

        nodes = grouped_endpoints(endpoint_records).map.with_index do |node, index|
          build_junction_node(scope_key, room_token, node, index)
        end.compact

        {
          :nodes => nodes,
          :overrides => wall_overrides_from_nodes(nodes)
        }
      end

      def grouped_endpoints(records)
        Array(records).each_with_object([]) do |record, groups|
          group = groups.find do |candidate|
            candidate[:anchor].distance(record[:point]) <= TOLERANCE
          end

          if group
            group[:members] << record
            group[:points] << record[:point]
            group[:anchor] = average_point(group[:points])
          else
            groups << {
              :anchor => record[:point],
              :points => [record[:point]],
              :members => [record]
            }
          end
        end.select do |node|
          node[:members].map { |member| member[:wall_id] }.uniq.length > 1
        end.sort_by do |node|
          [node[:anchor].x, node[:anchor].y, node[:anchor].z]
        end
      end

      def build_junction_node(scope_key, room_token, node, index)
        members = node[:members]
        return nil if members.length < 2

        connected_walls = members.map { |member| member[:wall_group] }.uniq
        primary_wall = connected_walls.min_by do |wall_group|
          [wall_group.get_attribute(PLUGIN_ID, 'room_sequence', 10_000).to_i, wall_group.persistent_id]
        end
        return nil unless primary_wall

        stubs = members.map do |member|
          endpoint_stub(member[:wall], member[:endpoint])
        end.compact
        return nil if stubs.empty?

        connected_wall_ids = connected_walls.map(&:persistent_id).sort
        base_z = members.map { |member| member[:wall][:base_z].to_f }.min
        top_z = members.map { |member| member[:wall][:base_z].to_f + member[:wall][:height].to_f }.max
        footprint = compact_junction_footprint(members, stubs)
        projections = members.each_with_object({}) do |member, result|
          result[member[:wall_id]] = project_junction_footprint_onto_wall(footprint, member[:wall])
        end

        {
          :id => "#{scope_key}_junction_#{index}",
          :scope_key => scope_key,
          :room_token => room_token,
          :kind => junction_kind_for_members(connected_wall_ids.length),
          :primary_wall_id => primary_wall.persistent_id,
          :connected_wall_ids => connected_wall_ids,
          :base_z => base_z,
          :height => top_z - base_z,
          :max_thickness => members.map { |member| member[:wall][:thickness].to_f }.max,
          :footprint_points => footprint,
          :footprint_depth => footprint_depth_for(footprint, members.first[:wall]),
          :members => members.map do |member|
            {
              :wall_id => member[:wall_id],
              :endpoint => member[:endpoint]
            }
          end,
          :stubs => stubs,
          :projections => projections
        }
      end

      def wall_overrides_from_nodes(nodes)
        Array(nodes).each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |node, overrides|
          node[:members].each do |member|
            range = node[:projections][member[:wall_id]]
            next unless range && segment_length(range) > TOLERANCE

            overrides[member[:wall_id]][:"#{member[:endpoint]}_column"] = {
              :range => range,
              :junction_id => node[:id],
              :junction_kind => node[:kind],
              :connected_wall_ids => node[:connected_wall_ids],
              :primary_wall_id => node[:primary_wall_id]
            }
          end
        end
      end

      def endpoint_stub(wall, endpoint)
        stub_length = [STRUCTURE_DEPTH.to_f, wall[:length].to_f].min
        return nil if stub_length <= TOLERANCE

        endpoint_point = endpoint == :start ? wall[:start_point] : wall[:end_point]
        axis = endpoint == :start ? wall[:axis] : reverse_vector(wall[:axis])
        near_left = offset_point(endpoint_point, wall[:left_axis], wall[:left_extent])
        far_left = offset_point(offset_point(endpoint_point, axis, stub_length), wall[:left_axis], wall[:left_extent])
        far_right = offset_point(offset_point(endpoint_point, axis, stub_length), wall[:left_axis], -wall[:right_extent])
        near_right = offset_point(endpoint_point, wall[:left_axis], -wall[:right_extent])

        {
          :endpoint => endpoint,
          :points => [near_left, far_left, far_right, near_right]
        }
      end

      def compact_junction_footprint(members, stubs)
        if Array(members).length == 2
          origin = average_point(Array(members).map { |member| member[:point] })
          reference_wall = members.first[:wall]
          side = members.map { |member| member[:wall][:thickness].to_f }.max
          return centered_square_footprint(origin, reference_wall, side)
        end

        reference_wall = members.first[:wall]
        origin = average_point(Array(stubs).flat_map { |stub| stub[:points] })
        x_axis = reference_wall[:axis]
        y_axis = reference_wall[:left_axis]
        projected = Array(stubs).flat_map do |stub|
          Array(stub[:points]).map do |point|
            [
              (point - origin).dot(x_axis),
              (point - origin).dot(y_axis)
            ]
          end
        end

        min_x = projected.map(&:first).min
        max_x = projected.map(&:first).max
        min_y = projected.map(&:last).min
        max_y = projected.map(&:last).max

        [
          offset_point(offset_point(origin, x_axis, min_x), y_axis, min_y),
          offset_point(offset_point(origin, x_axis, max_x), y_axis, min_y),
          offset_point(offset_point(origin, x_axis, max_x), y_axis, max_y),
          offset_point(offset_point(origin, x_axis, min_x), y_axis, max_y)
        ]
      end

      def centered_square_footprint(origin, wall, side)
        half = side.to_f / 2.0
        [
          offset_point(offset_point(origin, wall[:axis], -half), wall[:left_axis], -half),
          offset_point(offset_point(origin, wall[:axis], half), wall[:left_axis], -half),
          offset_point(offset_point(origin, wall[:axis], half), wall[:left_axis], half),
          offset_point(offset_point(origin, wall[:axis], -half), wall[:left_axis], half)
        ]
      end

      def project_junction_footprint_onto_wall(points, wall)
        distances = Array(points).map do |point|
            clamp(project_distance_on_wall(point, wall), 0.0, wall[:length].to_f)
        end
        return nil if distances.empty?

        [distances.min, distances.max]
      end

      def footprint_depth_for(points, wall)
        distances = Array(points).map do |point|
          ((point - wall[:start_point]).dot(wall[:left_axis])).abs
        end
        distances.max.to_f
      end

      def project_distance_on_wall(point, wall)
        (point - wall[:start_point]).dot(wall[:axis])
      end

      def average_point(points)
        count = Array(points).length.to_f
        return Geom::Point3d.new(0, 0, 0) if count.zero?

        Geom::Point3d.new(
          Array(points).sum(&:x) / count,
          Array(points).sum(&:y) / count,
          Array(points).sum(&:z) / count
        )
      end

      def junction_kind_for_members(count)
        case count.to_i
        when 2
          'corner'
        when 3
          'tee'
        else
          'cross'
        end
      end

      def room_physical_walls(walls)
        Array(walls).select { |wall| GeometryBuilder.physical_wall_group?(wall) }
      end

      def room_conversion_present?(model, room_token, walls)
        return true unless room_junction_groups_for_token(model, room_token).empty?

        room_physical_walls(walls).any? do |wall|
          !block_groups_for_wall(model, wall).empty? || wall.get_attribute(PLUGIN_ID, 'has_block_conversion', false)
        end
      end

      def connected_physical_wall_cluster(model, wall_group)
        return [] unless model && wall_group&.valid?
        return [] unless GeometryBuilder.physical_wall_group?(wall_group)
        return [wall_group] unless GeometryBuilder.room_token(wall_group).to_s.empty?

        candidates = model.active_entities.grep(Sketchup::Group).select do |group|
          GeometryBuilder.physical_wall_group?(group) && GeometryBuilder.room_token(group).to_s.empty?
        end
        return [wall_group] unless candidates.include?(wall_group)

        wall_cache = {}
        queue = [wall_group]
        cluster = []
        visited = {}

        until queue.empty?
          current = queue.shift
          next if visited[current.persistent_id]

          visited[current.persistent_id] = true
          cluster << current
          current_info = wall_cache[current.persistent_id] ||= GeometryBuilder.wall_info(current)
          next unless current_info

          candidates.each do |candidate|
            next if visited[candidate.persistent_id]

            candidate_info = wall_cache[candidate.persistent_id] ||= GeometryBuilder.wall_info(candidate)
            next unless candidate_info
            next unless walls_share_endpoint?(current_info, candidate_info)

            queue << candidate
          end
        end

        cluster.uniq
      end

      def walls_share_endpoint?(wall_a, wall_b)
        [wall_a[:start_point], wall_a[:end_point]].any? do |point_a|
          [wall_b[:start_point], wall_b[:end_point]].any? do |point_b|
            point_a.distance(point_b) <= TOLERANCE
          end
        end
      end

      def cluster_scope_key(walls)
        "cluster:#{Array(walls).map(&:persistent_id).sort.join('-')}"
      end

      def cluster_walls_for_scope(model, scope_key)
        key = scope_key.to_s
        return [] if key.empty?

        model.active_entities.grep(Sketchup::Group).select do |group|
          GeometryBuilder.physical_wall_group?(group) && group.get_attribute(PLUGIN_ID, 'conversion_scope_key').to_s == key
        end
      end

      def cluster_conversion_present?(model, walls)
        scope_key = cluster_scope_key(walls)
        return true unless cluster_junction_groups_for_scope(model, scope_key).empty?

        Array(walls).any? do |wall|
          !block_groups_for_wall(model, wall).empty? || wall.get_attribute(PLUGIN_ID, 'has_block_conversion', false)
        end
      end

      def rebuild_connected_cluster_hosts(walls, keep_hidden = false)
        cluster_walls = Array(walls).select(&:valid?).uniq
        return cluster_walls if cluster_walls.length < 2

        snapshots = cluster_walls.each_with_object({}) do |wall_group, result|
          wall = GeometryBuilder.wall_info(wall_group)
          next unless wall

          result[wall_group.persistent_id] = {
            :group => wall_group,
            :wall => wall,
            :settings => GeometryBuilder.entity_settings(wall_group),
            :openings => GeometryBuilder.opening_records(wall_group)
          }
        end
        return cluster_walls if snapshots.length < 2

        snapshots.each_value do |snapshot|
          wall = snapshot[:wall]
          GeometryBuilder.rebuild_wall_with_openings(
            snapshot[:group],
            wall[:start_point],
            wall[:end_point],
            snapshot[:settings],
            connected_cluster_adjacent_point(snapshots, snapshot, :start),
            connected_cluster_adjacent_point(snapshots, snapshot, :end),
            snapshot[:openings]
          )
          snapshot[:group].hidden = keep_hidden if snapshot[:group]&.valid?
        end

        cluster_walls
      end

      def remove_connected_cluster_conversion(model, walls, keep_host_hidden = false)
        cluster_walls = Array(walls).select(&:valid?).uniq
        return true if cluster_walls.empty?

        scope_key = cluster_scope_key(cluster_walls)
        groups = cluster_walls.flat_map { |wall| block_groups_for_wall(model, wall) }
        groups.concat(cluster_junction_groups_for_scope(model, scope_key))
        groups.select!(&:valid?)
        model.active_entities.erase_entities(groups) unless groups.empty?
        rebuild_connected_cluster_hosts(cluster_walls, keep_host_hidden) unless keep_host_hidden

        cluster_walls.each do |wall|
          clear_conversion_state(wall)
          wall.hidden = false if wall.valid? && !keep_host_hidden
        end
        true
      end

      def remove_room_conversion(model, room_token, walls = nil, keep_host_hidden = false)
        token = room_token.to_s
        return true if token.empty?

        snapshot = RoomRegenerator.room_snapshot(model, token)
        room_walls = room_physical_walls(walls || snapshot[:walls])
        groups = room_walls.flat_map { |wall| block_groups_for_wall(model, wall) }
        groups.concat(room_junction_groups_for_token(model, token))
        groups.select!(&:valid?)
        model.active_entities.erase_entities(groups) unless groups.empty?

        room_walls.each do |wall|
          clear_conversion_state(wall)
          wall.hidden = false if wall.valid? && !keep_host_hidden
        end
        true
      end

      def clamp(value, minimum, maximum)
        [[value.to_f, minimum.to_f].max, maximum.to_f].min
      end

      def connected_cluster_adjacent_point(snapshots, snapshot, endpoint)
        wall = snapshot[:wall]
        anchor = endpoint == :start ? wall[:start_point] : wall[:end_point]
        neighbors = snapshots.each_value.with_object([]) do |candidate, result|
          next if candidate[:group] == snapshot[:group]

          candidate_wall = candidate[:wall]
          touch_start = candidate_wall[:start_point].distance(anchor) <= TOLERANCE
          touch_end = candidate_wall[:end_point].distance(anchor) <= TOLERANCE
          next unless touch_start || touch_end

          result << {
            :candidate => candidate,
            :adjacent_point => touch_start ? candidate_wall[:end_point] : candidate_wall[:start_point]
          }
        end
        return nil unless neighbors.length == 1

        neighbors.first[:adjacent_point]
      end

      def symbolize(payload)
        return {} unless payload.is_a?(Hash)

        payload.each_with_object({}) do |(key, value), result|
          result[key.to_s.strip.downcase.gsub(/\s+/, '_').to_sym] = value
        end
      end

      def to_cm(length)
        length.to_f / 1.cm.to_f
      end
    end
  end
end
