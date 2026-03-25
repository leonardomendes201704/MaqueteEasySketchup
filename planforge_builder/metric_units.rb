module LeonardoLabs
  module PlanForgeBuilder
    module MetricUnits
      extend self

      METERS_PER_CENTIMETER = 0.01
      SUPPORTED_UNITS = {
        'mm' => 0.1,
        'milimetro' => 0.1,
        'milimetros' => 0.1,
        'millimeter' => 0.1,
        'millimeters' => 0.1,
        'cm' => 1.0,
        'centimetro' => 1.0,
        'centimetros' => 1.0,
        'centimeter' => 1.0,
        'centimeters' => 1.0,
        'm' => 100.0,
        'metro' => 100.0,
        'metros' => 100.0,
        'meter' => 100.0,
        'meters' => 100.0
      }.freeze

      def format_meters(length, precision = 2)
        centimeters = length.to_f / 1.cm
        meters = centimeters * METERS_PER_CENTIMETER
        number = format("%.#{precision}f", meters).tr('.', ',')
        "#{number} m"
      end

      def meter_field_value(length, precision = 2)
        format_meters(length, precision).delete_suffix(' m')
      end

      def parse_length(value, default_unit = 'm')
        return value.to_f.m if value.is_a?(Numeric)

        text = value.to_s.strip.downcase
        raise ArgumentError, 'Informe uma medida valida.' if text.empty?

        normalized = text.tr(',', '.').gsub(/\s+/, ' ')
        matcher = normalized.match(/\A(-?\d+(?:\.\d+)?)\s*([[:alpha:]]+)?\z/)
        raise ArgumentError, "Nao foi possivel interpretar a medida '#{value}'." unless matcher

        numeric_value = Float(matcher[1])
        unit = matcher[2].to_s
        unit = default_unit if unit.empty?
        factor_cm = SUPPORTED_UNITS[unit]
        raise ArgumentError, "Unidade '#{unit}' nao suportada. Use m, cm ou mm." unless factor_cm

        numeric_value * factor_cm.cm
      rescue ArgumentError
        raise
      rescue StandardError
        raise ArgumentError, "Nao foi possivel interpretar a medida '#{value}'."
      end
    end
  end
end
