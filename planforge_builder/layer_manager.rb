module LeonardoLabs
  module PlanForgeBuilder
    module LayerManager
      extend self

      LAYER_NAMES = {
        :wall => 'Walls',
        :floor => 'Floors',
        :baseboard => 'Baseboards'
      }.freeze

      def apply_to_entity(entity, kind)
        return entity unless entity&.valid?

        layer = ensure_layer(entity.model, kind)
        default_layer = default_layer_for(entity.model)
        entity.layer = layer if entity.respond_to?(:layer=)
        normalize_nested_layers(entity, default_layer)
        entity.set_attribute(PLUGIN_ID, 'layer_role', kind.to_s)
        entity
      end

      def ensure_layer(model, kind)
        name = LAYER_NAMES[kind.to_sym]
        raise ArgumentError, "Tipo de layer invalido: #{kind}" unless name

        layers = model.layers
        layers[name] || layers.add(name)
      end

      private

      def default_layer_for(model)
        model.layers['Layer0'] || model.layers[0]
      end

      def normalize_nested_layers(entity, default_layer)
        return unless entity.respond_to?(:entities)

        entity.entities.each do |child|
          next unless child.respond_to?(:layer=)

          child.layer = default_layer
          normalize_nested_layers(child, default_layer)
        end
      end
    end
  end
end
