module LeonardoLabs
  module PlanForgeBuilder
    module MaterialManager
      extend self

      MATERIAL_TYPES = {
        :wall => {
          :name_key => :wall_material_name,
          :color_key => :wall_material_color
        },
        :floor => {
          :name_key => :floor_material_name,
          :color_key => :floor_material_color
        },
        :baseboard => {
          :name_key => :baseboard_material_name,
          :color_key => :baseboard_material_color
        }
      }.freeze

      def apply_to_entity(entity, kind, settings = Settings.to_h, force = false)
        return entity unless entity&.valid?

        sanitized = Settings.sanitize(settings)
        return entity unless force || sanitized[:apply_materials_on_create]

        config = MATERIAL_TYPES[kind.to_sym]
        return entity unless config

        material = ensure_material(entity.model, kind, sanitized)
        paint_group(entity, material)
        entity.set_attribute(PLUGIN_ID, 'material_role', kind.to_s)
        entity
      end

      def ensure_material(model, kind, settings = Settings.to_h)
        config = MATERIAL_TYPES[kind.to_sym]
        raise ArgumentError, "Tipo de material invalido: #{kind}" unless config

        sanitized = Settings.sanitize(settings)
        name = sanitized[config[:name_key]]
        color = color_from_hex(sanitized[config[:color_key]])
        materials = model.materials
        material = materials[name] || materials.add(name)
        material.color = color
        material
      end

      private

      def paint_group(group, material)
        group.material = material if group.respond_to?(:material=)
        paint_entities(group.entities, material) if group.respond_to?(:entities)
      end

      def paint_entities(entities, material)
        entities.grep(Sketchup::Face).each do |face|
          face.material = material
          face.back_material = material
        end

        entities.grep(Sketchup::Group).each do |group|
          group.material = material
          paint_entities(group.entities, material)
        end
      end

      def color_from_hex(hex)
        normalized = hex.to_s.delete('#')
        red = normalized[0..1].to_i(16)
        green = normalized[2..3].to_i(16)
        blue = normalized[4..5].to_i(16)
        Sketchup::Color.new(red, green, blue)
      end
    end
  end
end
