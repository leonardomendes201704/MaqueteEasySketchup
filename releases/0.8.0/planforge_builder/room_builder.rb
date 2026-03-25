module LeonardoLabs
  module PlanForgeBuilder
    module RoomBuilder
      extend self

      TOLERANCE = 1.mm

      def preview_rect_room(anchor_point, interior_width, interior_depth, settings = Settings.to_h)
        sanitized = Settings.sanitize(settings)
        contour = rectangular_contour(anchor_point, interior_width, interior_depth, sanitized)
        floor_outline = GeometryBuilder.floor_outline_points(contour, sanitized)
        wall_previews = contour.each_with_index.map do |start_point, index|
          end_point = contour[(index + 1) % contour.length]
          prev_point = contour[(index - 1) % contour.length]
          next_point = contour[(index + 2) % contour.length]
          GeometryBuilder.preview_data(start_point, end_point, sanitized, prev_point, next_point)
        end

        {
          :anchor_point => anchor_point,
          :contour => contour,
          :floor_outline => floor_outline,
          :wall_previews => wall_previews,
          :width => interior_width,
          :depth => interior_depth,
          :label_point => Geom::Point3d.new(
            anchor_point.x + (interior_width / 2.0),
            anchor_point.y + (interior_depth / 2.0),
            anchor_point.z
          )
        }
      end

      def build_rect_room(model, anchor_point, interior_width, interior_depth, settings = Settings.to_h)
        sanitized = Settings.sanitize(settings)
        contour = rectangular_contour(anchor_point, interior_width, interior_depth, sanitized)
        build_room(model, contour, sanitized)
      end

      def build_room(model, contour_points, settings = Settings.to_h)
        sanitized = Settings.sanitize(settings)
        room_settings = sanitized.merge(
          :create_floor_on_close => true,
          :create_baseboard_on_close => true
        )
        contour = GeometryBuilder.normalized_contour_points(contour_points)
        raise ArgumentError, 'Nao foi possivel gerar um comodo com menos de 3 pontos.' if contour.length < 3

        walls = contour.each_with_index.map do |start_point, index|
          end_point = contour[(index + 1) % contour.length]
          prev_point = contour[(index - 1) % contour.length]
          next_point = contour[(index + 2) % contour.length]
          GeometryBuilder.build_wall(model, start_point, end_point, room_settings, prev_point, next_point)
        end

        room_token = GeometryBuilder.assign_room_metadata(walls, contour, room_settings)
        floor_group = nil
        baseboard_group = nil

        floor_group = GeometryBuilder.build_floor(model, contour, room_settings)
        GeometryBuilder.tag_room_entity(floor_group, contour, room_settings, room_token)
        baseboard_group = BaseboardBuilder.build_for_room(model, contour, walls, room_settings, room_token, true)

        {
          :room_token => room_token,
          :contour => contour,
          :walls => walls,
          :floor => floor_group,
          :baseboard => baseboard_group
        }
      end

      private

      def rectangular_contour(anchor_point, interior_width, interior_depth, settings)
        width = interior_width.to_f
        depth = interior_depth.to_f
        raise ArgumentError, 'A largura interna do comodo deve ser maior que zero.' if width <= TOLERANCE
        raise ArgumentError, 'A profundidade interna do comodo deve ser maior que zero.' if depth <= TOLERANCE

        margin = GeometryBuilder.room_interior_margin(settings)
        outer_origin_x = anchor_point.x - margin
        outer_origin_y = anchor_point.y - margin
        outer_width = width + (margin * 2.0)
        outer_depth = depth + (margin * 2.0)
        z_value = anchor_point.z

        [
          Geom::Point3d.new(outer_origin_x, outer_origin_y, z_value),
          Geom::Point3d.new(outer_origin_x + outer_width, outer_origin_y, z_value),
          Geom::Point3d.new(outer_origin_x + outer_width, outer_origin_y + outer_depth, z_value),
          Geom::Point3d.new(outer_origin_x, outer_origin_y + outer_depth, z_value)
        ]
      end
    end
  end
end
