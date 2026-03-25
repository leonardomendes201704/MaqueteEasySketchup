module LeonardoLabs
  module PlanForgeBuilder
    module GeometryBuilder
      extend self

      TOLERANCE = 1.mm

      def preview_data(start_point, end_point, settings = Settings.to_h)
        sanitized = Settings.sanitize(settings)
        footprint = footprint_points(start_point, end_point, sanitized)
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

      def build_wall(model, start_point, end_point, settings = Settings.to_h)
        sanitized = Settings.sanitize(settings)
        footprint = footprint_points(start_point, end_point, sanitized)

        group = model.active_entities.add_group
        group.name = 'PlanForge Wall'
        group.set_attribute(PLUGIN_ID, 'entity_type', 'wall')
        sanitized.each do |key, value|
          group.set_attribute(PLUGIN_ID, key.to_s, value)
        end

        face = group.entities.add_face(footprint)
        raise ArgumentError, 'Nao foi possivel criar a face base da parede.' unless face

        face.reverse! if face.normal.z < 0
        face.pushpull(sanitized[:wall_height_cm].to_f.cm)
        group
      end

      def footprint_points(start_point, end_point, settings = Settings.to_h)
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
          offset_point(start_point, left_vector, left_extent),
          offset_point(end_point, left_vector, left_extent),
          offset_point(end_point, left_vector, -right_extent),
          offset_point(start_point, left_vector, -right_extent)
        ]
      end

      def flat_direction_vector(start_point, end_point)
        vector = end_point - start_point
        Geom::Vector3d.new(vector.x, vector.y, 0.0)
      end

      private

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
