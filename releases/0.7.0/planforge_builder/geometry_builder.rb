module LeonardoLabs
  module PlanForgeBuilder
    module GeometryBuilder
      extend self

      TOLERANCE = 1.mm

      def preview_data(start_point, end_point, settings = Settings.to_h, prev_point = nil, next_point = nil)
        sanitized = Settings.sanitize(settings)
        footprint = footprint_points(start_point, end_point, sanitized, prev_point, next_point)
        height = sanitized[:wall_height_cm].to_f.cm
        top = footprint.map { |point| point.offset(Z_AXIS, height) }

        {
          :footprint => footprint,
          :top => top,
          :midpoint => midpoint(start_point, end_point, height),
          :length => start_point.distance(end_point),
          :vector => flat_direction_vector(start_point, end_point),
          :height => height
        }
      end

      def build_wall(model, start_point, end_point, settings = Settings.to_h, prev_point = nil, next_point = nil)
        sanitized = Settings.sanitize(settings)

        group = model.active_entities.add_group
        group.name = 'PlanForge Wall'
        rebuild_wall(group, start_point, end_point, sanitized, prev_point, next_point)
        group
      end

      def rebuild_wall(group, start_point, end_point, settings = Settings.to_h, prev_point = nil, next_point = nil)
        sanitized = Settings.sanitize(settings)
        footprint = footprint_points(start_point, end_point, sanitized, prev_point, next_point)
        entities = group.entities
        existing = entities.to_a
        entities.erase_entities(existing) unless existing.empty?

        group.set_attribute(PLUGIN_ID, 'entity_type', 'wall')
        store_entity_settings(group, sanitized)
        store_wall_metadata(group, start_point, end_point)

        face = entities.add_face(footprint)
        raise ArgumentError, 'Nao foi possivel criar a face base da parede.' unless face

        face.reverse! if face.normal.z < 0
        face.pushpull(sanitized[:wall_height_cm].to_f.cm)
        MaterialManager.apply_to_entity(group, :wall, sanitized)
        group
      end

      def build_floor(model, contour_points, settings = Settings.to_h)
        sanitized = Settings.sanitize(settings)
        outline = floor_outline_points(contour_points, sanitized)
        raise ArgumentError, 'Nao foi possivel criar o piso com menos de 3 pontos.' if outline.length < 3

        group = model.active_entities.add_group
        group.name = 'PlanForge Floor'
        group.set_attribute(PLUGIN_ID, 'entity_type', 'floor')
        sanitized.each do |key, value|
          group.set_attribute(PLUGIN_ID, key.to_s, value)
        end

        face = group.entities.add_face(outline)
        raise ArgumentError, 'Nao foi possivel criar a face do piso.' unless face

        face.reverse! if face.normal.z < 0
        face.pushpull(sanitized[:floor_thickness_cm].to_f.cm)
        MaterialManager.apply_to_entity(group, :floor, sanitized)
        group
      end

      def rebuild_wall_with_openings(group, start_point, end_point, settings = Settings.to_h, prev_point = nil, next_point = nil, openings = nil)
        records = Array(openings || opening_records(group)).map do |record|
          normalize_opening_record(record)
        end.compact

        rebuild_wall(group, start_point, end_point, settings, prev_point, next_point)
        store_opening_records(group, [])
        apply_opening_records(group, records)
        group
      end

      def entity_settings(entity)
        values = Settings::DEFAULTS.each_with_object({}) do |(key, default_value), result|
          result[key] = entity.get_attribute(PLUGIN_ID, key.to_s, default_value)
        end

        Settings.sanitize(values)
      end

      def store_entity_settings(entity, settings)
        Settings.sanitize(settings).each do |key, value|
          entity.set_attribute(PLUGIN_ID, key.to_s, value)
        end
      end

      def wall_info(group)
        wall_data(group)
      end

      def normalized_contour_points(contour_points)
        normalized_polygon_points(contour_points)
      end

      def room_interior_offset_distance(contour_points, settings = Settings.to_h)
        sanitized = Settings.sanitize(settings)
        points = normalized_polygon_points(contour_points)
        raise ArgumentError, 'Nao foi possivel calcular o offset interno sem um contorno valido.' if points.length < 3

        floor_offset_distance(points, sanitized)
      end

      def assign_room_metadata(wall_groups, contour_points, settings = Settings.to_h, room_token = nil)
        sanitized = Settings.sanitize(settings)
        points = normalized_polygon_points(contour_points)
        return nil if points.length < 3

        room_token ||= generate_room_token
        contour_payload = JSON.generate(points.map { |point| point_to_a(point) })
        interior_offset = floor_offset_distance(points, sanitized)

        Array(wall_groups).each_with_index do |group, index|
          next unless wall_group?(group)

          group.set_attribute(PLUGIN_ID, 'room_token', room_token)
          group.set_attribute(PLUGIN_ID, 'room_sequence', index)
          group.set_attribute(PLUGIN_ID, 'room_contour', contour_payload)
          group.set_attribute(PLUGIN_ID, 'room_interior_offset', interior_offset)
        end

        room_token
      end

      def tag_room_entity(group, contour_points, settings = Settings.to_h, room_token = nil)
        return group unless group

        sanitized = Settings.sanitize(settings)
        points = normalized_polygon_points(contour_points)
        return group if points.length < 3

        room_token ||= group.get_attribute(PLUGIN_ID, 'room_token')
        room_token ||= generate_room_token
        group.set_attribute(PLUGIN_ID, 'room_token', room_token)
        group.set_attribute(PLUGIN_ID, 'room_contour', JSON.generate(points.map { |point| point_to_a(point) }))
        group.set_attribute(PLUGIN_ID, 'room_interior_offset', floor_offset_distance(points, sanitized))
        group
      end

      def room_token(entity)
        entity.respond_to?(:get_attribute) ? entity.get_attribute(PLUGIN_ID, 'room_token') : nil
      end

      def room_contour(entity)
        payload = entity.respond_to?(:get_attribute) ? entity.get_attribute(PLUGIN_ID, 'room_contour') : nil
        contour_from_json(payload)
      end

      def opening_records(group)
        payload = group.get_attribute(PLUGIN_ID, 'openings')
        records = JSON.parse(payload.to_s)
        Array(records).each_with_index.map do |record, index|
          normalize_opening_record(record, index)
        end
      rescue StandardError
        []
      end

      def store_opening_records(group, records)
        normalized = Array(records).each_with_index.map do |record, index|
          normalize_opening_record(record, index)
        end.compact
        group.set_attribute(PLUGIN_ID, 'openings', JSON.generate(normalized.map { |record| opening_record_payload(record) }))
      rescue StandardError => error
        Diagnostics.error('geometry_builder.store_opening_records', error)
      end

      def wall_group?(entity)
        entity.is_a?(Sketchup::Group) && entity.get_attribute(PLUGIN_ID, 'entity_type') == 'wall'
      end

      def door_preview_data(group, world_point, settings = Settings.to_h)
        opening_preview_data(group, world_point, settings, :door)
      end

      def window_preview_data(group, world_point, settings = Settings.to_h)
        opening_preview_data(group, world_point, settings, :window)
      end

      def cut_door_opening(group, preview_or_world_point, settings = Settings.to_h)
        preview = preview_or_world_point.is_a?(Hash) ? preview_or_world_point : door_preview_data(group, preview_or_world_point, settings)
        cut_opening(group, preview)
      end

      def cut_window_opening(group, preview_or_world_point, settings = Settings.to_h)
        preview = preview_or_world_point.is_a?(Hash) ? preview_or_world_point : window_preview_data(group, preview_or_world_point, settings)
        cut_opening(group, preview)
      end

      def opening_preview_data(group, world_point, settings = Settings.to_h, kind = :door)
        return nil unless wall_group?(group)

        wall = wall_data(group)
        return nil unless wall

        sanitized = Settings.sanitize(settings)
        width, height = opening_dimensions(kind, sanitized, wall)
        return nil if width <= TOLERANCE || height <= TOLERANCE

        clearance = [1.cm.to_f, wall[:thickness] / 2.0].max
        min_distance = clearance + (width / 2.0)
        max_distance = wall[:length] - clearance - (width / 2.0)
        return nil if max_distance < min_distance

        local_point = world_to_local(group, world_point)
        center_distance = clamp(project_distance(local_point, wall[:start_point], wall[:axis]), min_distance, max_distance)
        center_point = offset_point(wall[:start_point], wall[:axis], center_distance)
        bottom_z, top_z, snapped_top = opening_vertical_span(kind, wall, local_point, sanitized, height)
        surface_offset, opposite_offset = surface_offsets_for_point(wall, local_point, center_point)
        depth_delta = opposite_offset - surface_offset
        through_vector = Geom::Vector3d.new(
          wall[:left_axis].x * depth_delta,
          wall[:left_axis].y * depth_delta,
          wall[:left_axis].z * depth_delta
        )

        local_face = build_opening_face(center_point, wall[:axis], wall[:left_axis], surface_offset, width, bottom_z, top_z)
        local_back = local_face.map { |point| offset_point(point, wall[:left_axis], depth_delta) }

        {
          :group => group,
          :kind => kind.to_s,
          :wall => wall,
          :opening_width => width,
          :opening_height => top_z - bottom_z,
          :center_distance => center_distance,
          :bottom_z => bottom_z,
          :top_z => top_z,
          :snapped_top => snapped_top,
          :local_face => local_face,
          :local_back => local_back,
          :through_vector => through_vector,
          :world_face => transform_points(group, local_face),
          :world_back => transform_points(group, local_back),
          :midpoint => local_to_world(group, midpoint_points(local_face[0], local_face[2]))
        }
      end

      def cut_opening(group, preview, persist_record = true)
        raise ArgumentError, 'Nao foi possivel posicionar a abertura nesta parede.' unless preview

        face = group.entities.add_face(preview[:local_face])
        raise ArgumentError, 'Nao foi possivel criar o recorte nesta parede.' unless face

        push_distance = face.normal.dot(preview[:through_vector]) >= 0.0 ? preview[:through_vector].length : -preview[:through_vector].length
        face.pushpull(push_distance)
        record_opening(group, preview) if persist_record
        group
      end

      def floor_outline_points(contour_points, settings = Settings.to_h)
        sanitized = Settings.sanitize(settings)
        points = normalized_polygon_points(contour_points)
        raise ArgumentError, 'Nao foi possivel calcular o contorno do piso com menos de 3 pontos.' if points.length < 3

        offset = floor_offset_distance(points, sanitized)
        outline = points.each_with_index.map do |point, index|
          next_point = points[(index + 1) % points.length]
          prev_point = points[(index - 1) % points.length]
          direction = flat_direction_vector(point, next_point)

          raise ArgumentError, 'Nao foi possivel calcular o contorno interno do piso.' if direction.length <= TOLERANCE

          joined_offset_point(point, direction, prev_point, offset, true)
        end

        normalized_polygon_points(outline)
      end

      def footprint_points(start_point, end_point, settings = Settings.to_h, prev_point = nil, next_point = nil)
        sanitized = Settings.sanitize(settings)
        thickness = sanitized[:wall_thickness_cm].to_f.cm
        direction = flat_direction_vector(start_point, end_point)

        raise ArgumentError, 'Comprimento insuficiente para criar a parede.' if direction.length <= TOLERANCE

        direction.normalize!
        left_vector = Z_AXIS.cross(direction)
        raise ArgumentError, 'Nao foi possivel calcular o perfil da parede.' if left_vector.length <= 0.0

        left_vector.normalize!
        left_extent, right_extent = extents_for_alignment(sanitized[:alignment], thickness)

        [
          joined_offset_point(start_point, direction, prev_point, left_extent, true),
          joined_offset_point(end_point, direction, next_point, left_extent, false),
          joined_offset_point(end_point, direction, next_point, -right_extent, false),
          joined_offset_point(start_point, direction, prev_point, -right_extent, true)
        ]
      end

      def flat_direction_vector(start_point, end_point)
        vector = end_point - start_point
        Geom::Vector3d.new(vector.x, vector.y, 0.0)
      end

      private

      def generate_room_token
        "room-#{Time.now.to_f.to_s.tr('.', '_')}-#{rand(1000..9999)}"
      end

      def opening_dimensions(kind, settings, wall)
        case kind.to_sym
        when :window
          width = settings[:window_width_cm].to_f.cm
          height = [settings[:window_height_cm].to_f.cm, wall[:height] - 2.cm.to_f].min
        else
          width = settings[:door_width_cm].to_f.cm
          height = [settings[:door_height_cm].to_f.cm, wall[:height]].min
        end

        [width, height]
      end

      def opening_vertical_span(kind, wall, local_point, settings, height)
        case kind.to_sym
        when :window
          window_vertical_span(wall, local_point, settings, height)
        else
          door_top = wall[:base_z] + height
          [wall[:base_z], door_top, true]
        end
      end

      def window_vertical_span(wall, local_point, settings, height)
        min_bottom = wall[:base_z] + 1.cm.to_f
        max_top = wall[:base_z] + wall[:height] - 1.cm.to_f
        desired_center = clamp(local_point.z, min_bottom + (height / 2.0), max_top - (height / 2.0))
        top_z = desired_center + (height / 2.0)

        snap_target = wall[:base_z] + settings[:door_height_cm].to_f.cm
        snap_threshold = [(settings[:snap_step_cm].to_f.cm / 2.0), 6.cm.to_f].max
        snapped_top = false

        if snap_target >= (min_bottom + height) && snap_target <= max_top && (top_z - snap_target).abs <= snap_threshold
          top_z = snap_target
          snapped_top = true
        end

        bottom_z = top_z - height
        if bottom_z < min_bottom
          bottom_z = min_bottom
          top_z = bottom_z + height
          snapped_top = false
        elsif top_z > max_top
          top_z = max_top
          bottom_z = top_z - height
          snapped_top = false
        end

        [bottom_z, top_z, snapped_top]
      end

      def store_wall_metadata(group, start_point, end_point)
        group.set_attribute(PLUGIN_ID, 'start_point', point_to_a(start_point))
        group.set_attribute(PLUGIN_ID, 'end_point', point_to_a(end_point))
      end

      def apply_opening_records(group, records)
        applied_records = Array(records).each_with_object([]) do |record, result|
          preview = opening_preview_from_record(group, record)
          next unless preview

          cut_opening(group, preview, false)
          result << opening_record_from_preview(preview)
        end

        store_opening_records(group, applied_records)
      end

      def opening_preview_from_record(group, record)
        wall = wall_data(group)
        return nil unless wall

        normalized = normalize_opening_record(record)
        return nil unless normalized

        kind = normalized[:kind].to_sym
        width = clamp_opening_width(normalized[:opening_width], wall)
        return nil if width <= TOLERANCE

        center_distance = clamp_opening_center_distance(normalized[:center_distance], width, wall)
        bottom_z, top_z = clamp_opening_vertical_span(kind, normalized[:bottom_z], normalized[:top_z], wall)
        return nil if (top_z - bottom_z) <= TOLERANCE

        center_point = offset_point(wall[:start_point], wall[:axis], center_distance)
        surface_offset = wall[:left_extent]
        opposite_offset = -wall[:right_extent]
        depth_delta = opposite_offset - surface_offset
        local_face = build_opening_face(center_point, wall[:axis], wall[:left_axis], surface_offset, width, bottom_z, top_z)
        local_back = local_face.map { |point| offset_point(point, wall[:left_axis], depth_delta) }
        through_vector = Geom::Vector3d.new(
          wall[:left_axis].x * depth_delta,
          wall[:left_axis].y * depth_delta,
          wall[:left_axis].z * depth_delta
        )

        {
          :id => normalized[:id],
          :group => group,
          :kind => kind.to_s,
          :wall => wall,
          :opening_width => width,
          :opening_height => top_z - bottom_z,
          :center_distance => center_distance,
          :bottom_z => bottom_z,
          :top_z => top_z,
          :snapped_top => false,
          :local_face => local_face,
          :local_back => local_back,
          :through_vector => through_vector,
          :world_face => transform_points(group, local_face),
          :world_back => transform_points(group, local_back),
          :midpoint => local_to_world(group, midpoint_points(local_face[0], local_face[2]))
        }
      end

      def record_opening(group, preview)
        openings = opening_records(group)
        openings << opening_record_from_preview(preview)
        store_opening_records(group, openings)
      rescue StandardError => error
        Diagnostics.error('geometry_builder.record_opening', error)
      end

      def wall_data(group)
        start_point = point_from_attribute(group.get_attribute(PLUGIN_ID, 'start_point'))
        end_point = point_from_attribute(group.get_attribute(PLUGIN_ID, 'end_point'))
        inferred = infer_wall_segment(group) unless start_point && end_point

        start_point ||= inferred && inferred[:start_point]
        end_point ||= inferred && inferred[:end_point]
        return nil unless start_point && end_point

        if inferred
          store_wall_metadata(group, start_point, end_point)
          Diagnostics.write('Wall metadata inferred from geometry for door tool compatibility.')
        end

        settings = entity_settings(group)
        thickness = settings[:wall_thickness_cm].to_f.cm
        height = settings[:wall_height_cm].to_f.cm
        alignment = settings[:alignment]
        return nil if thickness <= TOLERANCE || height <= TOLERANCE

        axis = flat_direction_vector(start_point, end_point)
        return nil if axis.length <= TOLERANCE

        axis.normalize!
        left_axis = Z_AXIS.cross(axis)
        return nil if left_axis.length <= TOLERANCE

        left_axis.normalize!
        left_extent, right_extent = extents_for_alignment(alignment, thickness)

        {
          :start_point => start_point,
          :end_point => end_point,
          :axis => axis,
          :left_axis => left_axis,
          :length => start_point.distance(end_point),
          :thickness => thickness,
          :height => height,
          :base_z => [start_point.z, end_point.z].min,
          :left_extent => left_extent,
          :right_extent => right_extent
        }
      end

      def normalize_opening_record(record, index = nil)
        source = record.is_a?(Hash) ? record : {}
        kind = source[:kind] || source['kind']
        kind = kind.to_s.strip.downcase
        return nil unless %w[door window].include?(kind)

        center_distance = (source[:center_distance] || source['center_distance']).to_f
        opening_width = (source[:opening_width] || source['opening_width']).to_f
        bottom_z = (source[:bottom_z] || source['bottom_z']).to_f
        top_z = (source[:top_z] || source['top_z']).to_f
        return nil if opening_width <= TOLERANCE || (top_z - bottom_z) <= TOLERANCE

        {
          :id => (source[:id] || source['id']).to_s.strip.empty? ? opening_id(kind, index) : (source[:id] || source['id']).to_s,
          :kind => kind,
          :center_distance => center_distance,
          :opening_width => opening_width,
          :bottom_z => bottom_z,
          :top_z => top_z
        }
      end

      def opening_record_from_preview(preview)
        {
          :id => preview[:id].to_s.strip.empty? ? opening_id(preview[:kind], nil) : preview[:id].to_s,
          :kind => preview[:kind].to_s,
          :center_distance => preview[:center_distance].to_f,
          :opening_width => preview[:opening_width].to_f,
          :bottom_z => preview[:bottom_z].to_f,
          :top_z => preview[:top_z].to_f
        }
      end

      def opening_record_payload(record)
        {
          'id' => record[:id].to_s,
          'kind' => record[:kind].to_s,
          'center_distance' => record[:center_distance].to_f,
          'opening_width' => record[:opening_width].to_f,
          'bottom_z' => record[:bottom_z].to_f,
          'top_z' => record[:top_z].to_f
        }
      end

      def opening_id(kind, index)
        suffix = index ? (index + 1) : "#{Time.now.to_f.to_s.tr('.', '_')}-#{rand(1000..9999)}"
        "#{kind}-#{suffix}"
      end

      def clamp_opening_width(width, wall)
        max_width = [wall[:length] - (2.0 * [1.cm.to_f, wall[:thickness] / 2.0].max), TOLERANCE].max
        clamp(width.to_f, TOLERANCE, max_width)
      end

      def clamp_opening_center_distance(center_distance, width, wall)
        clearance = [1.cm.to_f, wall[:thickness] / 2.0].max
        minimum = clearance + (width / 2.0)
        maximum = wall[:length] - clearance - (width / 2.0)
        clamp(center_distance.to_f, minimum, maximum)
      end

      def clamp_opening_vertical_span(kind, bottom_z, top_z, wall)
        height = (top_z - bottom_z).to_f

        if kind == :door
          door_height = [[height, wall[:height]].min, 1.cm.to_f].max
          return [wall[:base_z], wall[:base_z] + door_height]
        end

        minimum_bottom = wall[:base_z] + 1.cm.to_f
        maximum_top = wall[:base_z] + wall[:height] - 1.cm.to_f
        height = [[height, maximum_top - minimum_bottom].min, 1.cm.to_f].max
        adjusted_bottom = clamp(bottom_z.to_f, minimum_bottom, maximum_top - height)
        [adjusted_bottom, adjusted_bottom + height]
      end

      def joined_offset_point(anchor_point, current_direction, adjacent_point, signed_offset, is_start)
        current_direction = current_direction.clone
        current_direction.normalize!
        current_left = Z_AXIS.cross(current_direction)
        current_left.normalize!
        current_origin = offset_point(anchor_point, current_left, signed_offset)
        return current_origin unless adjacent_point

        adjacent_direction = if is_start
                               flat_direction_vector(adjacent_point, anchor_point)
                             else
                               flat_direction_vector(anchor_point, adjacent_point)
                             end
        return current_origin if adjacent_direction.length <= TOLERANCE

        adjacent_direction.normalize!
        adjacent_left = Z_AXIS.cross(adjacent_direction)
        adjacent_left.normalize!
        adjacent_origin = offset_point(anchor_point, adjacent_left, signed_offset)

        intersect_lines_2d(current_origin, current_direction, adjacent_origin, adjacent_direction) || current_origin
      end

      def infer_wall_segment(group)
        base_edges = horizontal_base_edges(group)
        return nil if base_edges.length < 2

        primary = base_edges.max_by(&:length)
        return nil unless primary && primary.length > TOLERANCE

        primary_direction = edge_direction(primary)
        return nil if primary_direction.length <= TOLERANCE

        primary_direction.normalize!
        primary_start, primary_end = oriented_edge_points(primary, primary_direction)
        secondary = base_edges.reject { |edge| edge == primary }
                              .select { |edge| parallel_2d?(edge_direction(edge), primary_direction) }
                              .max_by { |edge| point_line_distance(edge_midpoint(edge), primary_start, primary_direction) }
        return nil unless secondary

        secondary_start, secondary_end = oriented_edge_points(secondary, primary_direction)

        {
          :start_point => midpoint_points(primary_start, secondary_start),
          :end_point => midpoint_points(primary_end, secondary_end)
        }
      end

      def intersect_lines_2d(point_a, direction_a, point_b, direction_b)
        determinant = (direction_a.x * direction_b.y) - (direction_a.y * direction_b.x)
        return nil if determinant.abs <= 1.0e-9

        delta_x = point_b.x - point_a.x
        delta_y = point_b.y - point_a.y
        factor = ((delta_x * direction_b.y) - (delta_y * direction_b.x)) / determinant

        Geom::Point3d.new(
          point_a.x + (direction_a.x * factor),
          point_a.y + (direction_a.y * factor),
          point_a.z
        )
      end

      def normalized_polygon_points(points)
        cleaned = Array(points).compact.map { |point| Geom::Point3d.new(point.x, point.y, point.z) }
        return [] if cleaned.empty?

        cleaned.pop while cleaned.length > 1 && cleaned.first.distance(cleaned.last) <= TOLERANCE
        deduplicate_sequential_points(cleaned)
      end

      def deduplicate_sequential_points(points)
        points.each_with_object([]) do |point, result|
          next if result.any? && result.last.distance(point) <= TOLERANCE

          result << point
        end
      end

      def floor_offset_distance(points, settings)
        left_extent, right_extent = extents_for_alignment(settings[:alignment], settings[:wall_thickness_cm].to_f.cm)
        polygon_area = signed_area(points)
        raise ArgumentError, 'Nao foi possivel determinar o lado interno do piso.' if polygon_area.abs <= 1.0e-6

        polygon_area.positive? ? left_extent : -right_extent
      end

      def signed_area(points)
        total = 0.0

        points.each_with_index do |point, index|
          next_point = points[(index + 1) % points.length]
          total += (point.x * next_point.y) - (next_point.x * point.y)
        end

        total / 2.0
      end

      def point_to_a(point)
        [point.x.to_f, point.y.to_f, point.z.to_f]
      end

      def point_from_attribute(value)
        return nil unless value.is_a?(Array) && value.length == 3

        Geom::Point3d.new(value[0].to_f, value[1].to_f, value[2].to_f)
      end

      def contour_from_json(payload)
        return [] if payload.to_s.strip.empty?

        JSON.parse(payload.to_s).map do |value|
          point_from_attribute(value)
        end.compact
      rescue StandardError
        []
      end

      def horizontal_base_edges(group)
        bounds = group.entities.bounds
        base_z = bounds.min.z

        group.entities.grep(Sketchup::Edge).select do |edge|
          next false if edge.length <= TOLERANCE

          start_point = edge.start.position
          end_point = edge.end.position
          (start_point.z - base_z).abs <= TOLERANCE &&
            (end_point.z - base_z).abs <= TOLERANCE &&
            (start_point.z - end_point.z).abs <= TOLERANCE
        end
      end

      def edge_direction(edge)
        flat_direction_vector(edge.start.position, edge.end.position)
      end

      def oriented_edge_points(edge, reference_direction)
        direction = edge_direction(edge)
        start_point = edge.start.position
        end_point = edge.end.position

        if direction.dot(reference_direction) < 0.0
          [end_point, start_point]
        else
          [start_point, end_point]
        end
      end

      def parallel_2d?(vector_a, vector_b)
        cross = (vector_a.x * vector_b.y) - (vector_a.y * vector_b.x)
        cross.abs <= 1.0e-6
      end

      def point_line_distance(point, line_point, line_direction)
        numerator = ((point.x - line_point.x) * line_direction.y) - ((point.y - line_point.y) * line_direction.x)
        numerator.abs / [line_direction.length, 1.0e-9].max
      end

      def edge_midpoint(edge)
        midpoint_points(edge.start.position, edge.end.position)
      end

      def midpoint_points(point_a, point_b)
        Geom::Point3d.new(
          (point_a.x + point_b.x) / 2.0,
          (point_a.y + point_b.y) / 2.0,
          (point_a.z + point_b.z) / 2.0
        )
      end

      def build_opening_face(center_point, axis, left_axis, surface_offset, width, bottom_z, top_z)
        start_point = offset_point(center_point, axis, -(width / 2.0))
        lower_start = offset_point(start_point, left_axis, surface_offset)
        lower_start.z = bottom_z
        lower_end = offset_point(lower_start, axis, width)
        upper_end = Geom::Point3d.new(lower_end.x, lower_end.y, top_z)
        upper_start = Geom::Point3d.new(lower_start.x, lower_start.y, top_z)
        [lower_start, lower_end, upper_end, upper_start]
      end

      def surface_offsets_for_point(wall, local_point, center_point)
        lateral_offset = (local_point - center_point).dot(wall[:left_axis])

        if lateral_offset >= 0.0
          [wall[:left_extent], -wall[:right_extent]]
        else
          [-wall[:right_extent], wall[:left_extent]]
        end
      end

      def world_to_local(group, point)
        point.transform(group.transformation.inverse)
      end

      def local_to_world(group, point)
        point.transform(group.transformation)
      end

      def transform_points(group, points)
        Array(points).map { |point| local_to_world(group, point) }
      end

      def project_distance(point, origin, axis)
        (point - origin).dot(axis)
      end

      def clamp(value, minimum, maximum)
        return minimum if value < minimum
        return maximum if value > maximum

        value
      end

      def extents_for_alignment(alignment, thickness)
        case alignment.to_s
        when 'left'
          [0.0, thickness]
        when 'right'
          [thickness, 0.0]
        else
          half = thickness / 2.0
          [half, half]
        end
      end

      def offset_point(point, vector, distance)
        Geom::Point3d.new(
          point.x + (vector.x * distance),
          point.y + (vector.y * distance),
          point.z + (vector.z * distance)
        )
      end

      def midpoint(start_point, end_point, height)
        Geom::Point3d.new(
          (start_point.x + end_point.x) / 2.0,
          (start_point.y + end_point.y) / 2.0,
          start_point.z + (height / 2.0)
        )
      end
    end
  end
end
