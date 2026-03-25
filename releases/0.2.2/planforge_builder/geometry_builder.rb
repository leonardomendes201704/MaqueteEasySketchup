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
        sanitized.each do |key, value|
          group.set_attribute(PLUGIN_ID, key.to_s, value)
        end

        face = entities.add_face(footprint)
        raise ArgumentError, 'Nao foi possivel criar a face base da parede.' unless face

        face.reverse! if face.normal.z < 0
        face.pushpull(sanitized[:wall_height_cm].to_f.cm)
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
