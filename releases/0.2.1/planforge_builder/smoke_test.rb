module LeonardoLabs
  module PlanForgeBuilder
    module SmokeTest
      extend self

      TRIGGER_PATH = File.join(ENV['TEMP'] || ROOT, 'planforge_builder_smoke_test.json').freeze
      RESULT_PATH = File.join(ENV['TEMP'] || ROOT, 'planforge_builder_smoke_test_result.json').freeze

      def run_if_requested
        return unless File.exist?(TRIGGER_PATH)

        payload = load_payload
        File.delete(TRIGGER_PATH) rescue nil
        Diagnostics.write('Smoke test requested.')

        UI.start_timer(1.0, false) do
          execute(payload)
        end
      end

      private

      def load_payload
        raw = File.read(TRIGGER_PATH)
        JSON.parse(raw.sub(/\A\uFEFF/, ''))
      rescue StandardError
        {}
      end

      def execute(payload)
        model = Sketchup.active_model
        original_settings = Settings.to_h
        requested_settings = Settings.sanitize(payload['settings'] || {})
        applied_settings = Settings.update(requested_settings)
        tool_selected = false
        floor_created = false
        corner_join_ok = false

        begin
          model.select_tool(WallTool.new)
          tool_selected = true
        rescue StandardError
          tool_selected = false
        ensure
          model.select_tool(nil)
        end

        model.start_operation('PlanForge Smoke Test', true)
        begin
          p1 = Geom::Point3d.new(0, 0, 0)
          p2 = Geom::Point3d.new(400.cm, 0, 0)
          p3 = Geom::Point3d.new(400.cm, 300.cm, 0)
          p4 = Geom::Point3d.new(0, 300.cm, 0)

          wall_one = GeometryBuilder.build_wall(model, p1, p2, applied_settings)
          wall_two = GeometryBuilder.build_wall(model, p2, p3, applied_settings)
          GeometryBuilder.rebuild_wall(wall_one, p1, p2, applied_settings, nil, p3)
          GeometryBuilder.rebuild_wall(wall_two, p2, p3, applied_settings, p1, nil)

          footprint_one = GeometryBuilder.footprint_points(p1, p2, applied_settings, nil, p3)
          footprint_two = GeometryBuilder.footprint_points(p2, p3, applied_settings, p1, nil)
          corner_join_ok = joint_points_match?(footprint_one, footprint_two)

          GeometryBuilder.build_floor(
            model,
            [
              p1,
              p2,
              p3,
              p4,
              p1
            ],
            applied_settings
          )
          floor_created = true
          model.abort_operation
        rescue StandardError
          model.abort_operation rescue nil
          raise
        end

        write_result(
          :status => 'ok',
          :plugin => EXTENSION_NAME,
          :version => EXTENSION_VERSION,
          :sketchup_version => Sketchup.version,
          :walls_tested => 2,
          :tool_selected => tool_selected,
          :corner_join_ok => corner_join_ok,
          :floor_created => floor_created,
          :settings => applied_settings
        )
        Diagnostics.write('Smoke test finished successfully.')
        quit_if_requested(payload)
      rescue StandardError => error
        write_result(
          :status => 'error',
          :plugin => EXTENSION_NAME,
          :version => EXTENSION_VERSION,
          :sketchup_version => Sketchup.version,
          :error_class => error.class.to_s,
          :error_message => error.message,
          :backtrace => Array(error.backtrace).first(10)
        )
        Diagnostics.error('smoke_test', error)
        quit_if_requested(payload)
      ensure
        Settings.update(original_settings) if original_settings
      end

      def write_result(payload)
        File.open(RESULT_PATH, 'w') do |file|
          file.write(JSON.pretty_generate(payload))
        end
      end

      def quit_if_requested(payload)
        return unless truthy?(payload['quit_after'])

        delay = payload['quit_delay'].to_f
        delay = 1.0 if delay <= 0.0
        UI.start_timer(delay, false) { Sketchup.quit }
      end

      def truthy?(value)
        value == true || %w[1 true yes on].include?(value.to_s.strip.downcase)
      end

      def joint_points_match?(footprint_one, footprint_two)
        shared_from_first = [footprint_one[1], footprint_one[2]]
        shared_from_second = [footprint_two[0], footprint_two[3]]

        shared_from_first.all? do |point|
          shared_from_second.any? { |candidate| candidate.distance(point) <= 0.1.mm }
        end
      end
    end
  end
end
