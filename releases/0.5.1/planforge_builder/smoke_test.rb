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
        door_tool_selected = false
        window_tool_selected = false
        floor_created = false
        baseboard_created = false
        baseboard_regenerated = false
        corner_join_ok = false
        floor_outline_ok = false
        floor_base_ok = false
        door_cut_ok = false
        window_cut_ok = false
        window_snap_ok = false
        window_free_move_ok = false
        baseboard_volume_ok = false
        baseboard_on_floor_ok = false

        begin
          model.select_tool(WallTool.new)
          tool_selected = true
        rescue StandardError
          tool_selected = false
        ensure
          model.select_tool(nil)
        end

        begin
          model.select_tool(DoorTool.new)
          door_tool_selected = true
        rescue StandardError
          door_tool_selected = false
        ensure
          model.select_tool(nil)
        end

        begin
          model.select_tool(WindowTool.new)
          window_tool_selected = true
        rescue StandardError
          window_tool_selected = false
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
          wall_three = GeometryBuilder.build_wall(model, p3, p4, applied_settings)
          wall_four = GeometryBuilder.build_wall(model, p4, p1, applied_settings)
          GeometryBuilder.rebuild_wall(wall_one, p1, p2, applied_settings, p4, p3)
          GeometryBuilder.rebuild_wall(wall_two, p2, p3, applied_settings, p1, p4)
          GeometryBuilder.rebuild_wall(wall_three, p3, p4, applied_settings, p2, p1)
          GeometryBuilder.rebuild_wall(wall_four, p4, p1, applied_settings, p3, p2)

          volume_before_door = wall_one.volume
          door_pick_point = Geom::Point3d.new(200.cm, 10.cm, 100.cm)
          GeometryBuilder.cut_door_opening(wall_one, door_pick_point, applied_settings)
          volume_after_door = wall_one.volume
          expected_door_volume = applied_settings[:door_width_cm].to_f.cm *
                                 applied_settings[:door_height_cm].to_f.cm *
                                 applied_settings[:wall_thickness_cm].to_f.cm
          door_cut_ok = (volume_before_door - volume_after_door - expected_door_volume).abs <= expected_door_volume * 0.02

          window_snap_point = Geom::Point3d.new(390.cm, 150.cm, 145.cm)
          window_free_point = Geom::Point3d.new(390.cm, 200.cm, 170.cm)
          snap_preview = GeometryBuilder.window_preview_data(wall_two, window_snap_point, applied_settings)
          free_preview = GeometryBuilder.window_preview_data(wall_two, window_free_point, applied_settings)
          window_snap_ok = snap_preview &&
                           snap_preview[:snapped_top] &&
                           (snap_preview[:top_z] - applied_settings[:door_height_cm].to_f.cm).abs <= 0.1.mm
          window_free_move_ok = free_preview &&
                                !free_preview[:snapped_top] &&
                                (free_preview[:top_z] - 230.cm).abs <= 0.1.mm

          volume_before_window = wall_two.volume
          GeometryBuilder.cut_window_opening(wall_two, snap_preview)
          volume_after_window = wall_two.volume
          expected_window_volume = applied_settings[:window_width_cm].to_f.cm *
                                   applied_settings[:window_height_cm].to_f.cm *
                                   applied_settings[:wall_thickness_cm].to_f.cm
          window_cut_ok = (volume_before_window - volume_after_window - expected_window_volume).abs <= expected_window_volume * 0.02

          footprint_one = GeometryBuilder.footprint_points(p1, p2, applied_settings, p4, p3)
          footprint_two = GeometryBuilder.footprint_points(p2, p3, applied_settings, p1, p4)
          corner_join_ok = joint_points_match?(footprint_one, footprint_two)

          room_token = GeometryBuilder.assign_room_metadata([wall_one, wall_two, wall_three, wall_four], [p1, p2, p3, p4, p1], applied_settings)

          floor_group = GeometryBuilder.build_floor(
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
          GeometryBuilder.tag_room_entity(floor_group, [p1, p2, p3, p4, p1], applied_settings, room_token)
          expected_outline = [
            Geom::Point3d.new(10.cm, 10.cm, 0),
            Geom::Point3d.new(390.cm, 10.cm, 0),
            Geom::Point3d.new(390.cm, 290.cm, 0),
            Geom::Point3d.new(10.cm, 290.cm, 0)
          ]
          computed_outline = GeometryBuilder.floor_outline_points([p1, p2, p3, p4, p1], applied_settings)
          floor_outline_ok = polygon_points_match?(computed_outline, expected_outline)
          floor_bounds = floor_group.bounds
          floor_base_ok = floor_bounds.min.z.abs <= 0.1.mm &&
                          (floor_bounds.max.z - applied_settings[:floor_thickness_cm].to_f.cm).abs <= 0.1.mm

          baseboard_group = BaseboardBuilder.build_for_room(model, [p1, p2, p3, p4, p1], [wall_one, wall_two, wall_three, wall_four], applied_settings, room_token, true)
          expected_baseboard_length = 1230.cm
          expected_baseboard_volume = expected_baseboard_length *
                                      applied_settings[:baseboard_height_cm].to_f.cm *
                                      applied_settings[:baseboard_depth_cm].to_f.cm
          baseboard_volume_ok = (sum_group_volumes(baseboard_group) - expected_baseboard_volume).abs <= expected_baseboard_volume * 0.03
          baseboard_created = !baseboard_group.nil? && baseboard_segment_count(baseboard_group) >= 4
          baseboard_on_floor_ok = baseboard_segment_min_z(baseboard_group) &&
                                  (baseboard_segment_min_z(baseboard_group) - floor_bounds.max.z).abs <= 0.1.mm

          model.selection.clear
          model.selection.add(wall_one)
          regenerated_groups = BaseboardBuilder.build_from_selection(model, model.selection, applied_settings)
          active_room_baseboards = model.active_entities.grep(Sketchup::Group).select do |group|
            group.get_attribute(PLUGIN_ID, 'entity_type') == 'baseboard' &&
              GeometryBuilder.room_token(group) == room_token
          end
          baseboard_regenerated = regenerated_groups.length == 1 && active_room_baseboards.length == 1
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
          :walls_tested => 4,
          :tool_selected => tool_selected,
          :door_tool_selected => door_tool_selected,
          :window_tool_selected => window_tool_selected,
          :corner_join_ok => corner_join_ok,
          :floor_outline_ok => floor_outline_ok,
          :floor_base_ok => floor_base_ok,
          :door_cut_ok => door_cut_ok,
          :window_cut_ok => window_cut_ok,
          :window_snap_ok => window_snap_ok,
          :window_free_move_ok => window_free_move_ok,
          :baseboard_created => baseboard_created,
          :baseboard_regenerated => baseboard_regenerated,
          :baseboard_volume_ok => baseboard_volume_ok,
          :baseboard_on_floor_ok => baseboard_on_floor_ok,
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

      def polygon_points_match?(actual_points, expected_points)
        return false unless actual_points.length == expected_points.length

        actual_points.all? do |point|
          expected_points.any? { |candidate| candidate.distance(point) <= 0.1.mm }
        end
      end

      def baseboard_segment_count(group)
        return 0 unless group

        group.entities.grep(Sketchup::Group).count do |entity|
          entity.get_attribute(PLUGIN_ID, 'entity_type') == 'baseboard_segment'
        end
      end

      def sum_group_volumes(group)
        return 0.0 unless group

        group.entities.grep(Sketchup::Group).sum do |entity|
          entity.volume.to_f
        end
      end

      def baseboard_segment_min_z(group)
        return nil unless group

        segments = group.entities.grep(Sketchup::Group).select do |entity|
          entity.get_attribute(PLUGIN_ID, 'entity_type') == 'baseboard_segment'
        end
        return nil if segments.empty?

        segments.map { |entity| entity.bounds.min.z }.min
      end
    end
  end
end
