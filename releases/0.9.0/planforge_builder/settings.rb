module LeonardoLabs
  module PlanForgeBuilder
    class Settings
      STORAGE_NAMESPACE = EXTENSION_NAME.dup.freeze
      ALIGNMENTS = %w[center left right].freeze
      MATERIAL_NAME_KEYS = %i[
        wall_material_name
        floor_material_name
        baseboard_material_name
      ].freeze
      MATERIAL_COLOR_KEYS = %i[
        wall_material_color
        floor_material_color
        baseboard_material_color
      ].freeze
      DEFAULTS = {
        :snap_step_cm => 10.0,
        :wall_thickness_cm => 15.0,
        :wall_height_cm => 280.0,
        :room_width_cm => 400.0,
        :room_depth_cm => 500.0,
        :floor_thickness_cm => 12.0,
        :baseboard_height_cm => 12.0,
        :baseboard_depth_cm => 1.5,
        :door_width_cm => 90.0,
        :door_height_cm => 210.0,
        :window_width_cm => 120.0,
        :window_height_cm => 120.0,
        :apply_materials_on_create => true,
        :wall_material_name => 'PlanForge Wall',
        :wall_material_color => '#E6E0D6',
        :floor_material_name => 'PlanForge Floor',
        :floor_material_color => '#D7C2A4',
        :baseboard_material_name => 'PlanForge Baseboard',
        :baseboard_material_color => '#F4EEE4',
        :create_floor_on_close => true,
        :create_baseboard_on_close => true,
        :ortho_mode => true,
        :alignment => 'center'
      }.freeze
      MINIMUMS = {
        :snap_step_cm => 1.0,
        :wall_thickness_cm => 1.0,
        :wall_height_cm => 10.0,
        :room_width_cm => 50.0,
        :room_depth_cm => 50.0,
        :floor_thickness_cm => 1.0,
        :baseboard_height_cm => 1.0,
        :baseboard_depth_cm => 0.5,
        :door_width_cm => 30.0,
        :door_height_cm => 100.0,
        :window_width_cm => 30.0,
        :window_height_cm => 30.0
      }.freeze

      class << self
        def current
          @current ||= load_settings
        end

        def to_h
          current.dup
        end

        def update(payload)
          @current = sanitize(current.merge(symbolize(payload)))
          persist(@current)
          @current.dup
        end

        def reset!
          @current = DEFAULTS.dup
          persist(@current)
          @current.dup
        end

        def sanitize(payload)
          normalized = symbolize(payload)
          values = DEFAULTS.dup

          DEFAULTS.each_key do |key|
            values[key] = sanitize_value(key, normalized.fetch(key, values[key]))
          end

          values
        end

        def length(key)
          current.fetch(key).to_f.cm
        end

        def ui_state(message = nil)
          state = current.dup
          state[:version] = EXTENSION_VERSION
          state[:message] = message
          state[:log_path] = Diagnostics.log_path
          state
        end

        private

        def load_settings
          stored = {}

          DEFAULTS.each do |key, default_value|
            stored[key] = Sketchup.read_default(STORAGE_NAMESPACE, key.to_s, default_value)
          end

          sanitize(stored)
        end

        def persist(values)
          values.each do |key, value|
            Sketchup.write_default(STORAGE_NAMESPACE, key.to_s, value)
          end
        end

        def sanitize_value(key, value)
          case key
          when :ortho_mode, :create_floor_on_close, :create_baseboard_on_close, :apply_materials_on_create
            truthy?(value)
          when :alignment
            alignment = value.to_s.strip.downcase
            ALIGNMENTS.include?(alignment) ? alignment : DEFAULTS[key]
          when *MATERIAL_NAME_KEYS
            sanitize_name(key, value)
          when *MATERIAL_COLOR_KEYS
            sanitize_color(key, value)
          else
            sanitize_numeric(key, value)
          end
        end

        def sanitize_numeric(key, value)
          parsed = parse_numeric(value)
          minimum = MINIMUMS[key] || 0.0
          return DEFAULTS[key] unless parsed && parsed.finite? && parsed > 0.0

          parsed = minimum if parsed < minimum
          parsed.round(2)
        end

        def parse_numeric(value)
          return value.to_f if value.is_a?(Numeric)

          cleaned = value.to_s.strip.tr(',', '.')
          Float(cleaned)
        rescue StandardError
          nil
        end

        def truthy?(value)
          return value if value == true || value == false

          %w[1 true yes on].include?(value.to_s.strip.downcase)
        end

        def sanitize_name(key, value)
          text = value.to_s.strip
          return DEFAULTS[key] if text.empty?

          text[0, 80]
        end

        def sanitize_color(key, value)
          text = value.to_s.strip
          text = "##{text}" unless text.start_with?('#')
          compact = text.delete('#')

          compact = compact.chars.map { |char| char * 2 }.join if compact.match?(/\A\h{3}\z/)
          return DEFAULTS[key] unless compact.match?(/\A\h{6}\z/)

          "##{compact.upcase}"
        end

        def symbolize(payload)
          return {} unless payload.is_a?(Hash)

          payload.each_with_object({}) do |(key, value), result|
            normalized_key = key.to_s.strip.downcase.gsub(/\s+/, '_').to_sym
            result[normalized_key] = value
          end
        end
      end
    end
  end
end
