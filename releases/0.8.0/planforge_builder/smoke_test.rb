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
        room_tool_selected = false
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
        parametric_selection_ok = false
        wall_parametric_edit_ok = false
        door_parametric_edit_ok = false
        window_parametric_edit_ok = false
        room_regeneration_ok = false
        wall_material_ok = false
        floor_material_ok = false
        baseboard_material_ok = false
        material_regeneration_ok = false
        wall_layer_ok = false
        floor_layer_ok = false
        baseboard_layer_ok = false
        layer_regeneration_ok = false
        room_generation_ok = false

        begin
          model.select_tool(RoomTool.new(400.cm, 500.cm, applied_settings))
          room_tool_selected = true
        rescue StandardError
          room_tool_selected = false
        ensure
          model.select_tool(nil)
        end

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

          generated_room = RoomBuilder.build_rect_room(
            model,
            Geom::Point3d.new(700.cm, 50.cm, 0),
            400.cm,
            500.cm,
            applied_settings
          )
          generated_floor = generated_room[:floor]
          generated_floor_bounds = generated_floor ? generated_floor.bounds : nil
          room_generation_ok = generated_room[:walls].length == 4 &&
                               generated_floor_bounds &&
                               generated_room[:baseboard] &&
                               generated_room[:room_token] &&
                               (generated_floor_bounds.min.x - 700.cm).abs <= 0.1.mm &&
                               (generated_floor_bounds.max.x - 1100.cm).abs <= 0.1.mm &&
                               (generated_floor_bounds.min.y - 50.cm).abs <= 0.1.mm &&
                               (generated_floor_bounds.max.y - 550.cm).abs <= 0.1.mm

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
          wall_layer_ok = layer_applied?(model, wall_one, :wall)
          floor_layer_ok = layer_applied?(model, floor_group, :floor)
          wall_material_ok = material_applied?(model, wall_one, :wall, applied_settings)
          floor_material_ok = material_applied?(model, floor_group, :floor, applied_settings)

          baseboard_group = BaseboardBuilder.build_for_room(model, [p1, p2, p3, p4, p1], [wall_one, wall_two, wall_three, wall_four], applied_settings, room_token, true)
          expected_baseboard_length = 1230.cm
          expected_baseboard_volume = expected_baseboard_length *
                                      applied_settings[:baseboard_height_cm].to_f.cm *
                                      applied_settings[:baseboard_depth_cm].to_f.cm
          baseboard_volume_ok = (sum_group_volumes(baseboard_group) - expected_baseboard_volume).abs <= expected_baseboard_volume * 0.03
          baseboard_created = !baseboard_group.nil? && baseboard_segment_count(baseboard_group) >= 4
          baseboard_on_floor_ok = baseboard_segment_min_z(baseboard_group) &&
                                  (baseboard_segment_min_z(baseboard_group) - floor_bounds.max.z).abs <= 0.1.mm
          baseboard_layer_ok = layer_applied?(model, baseboard_group, :baseboard) &&
                               nested_groups_on_default_layer?(model, baseboard_group)
          baseboard_material_ok = material_applied?(model, baseboard_group, :baseboard, applied_settings) &&
                                  nested_group_materials_match?(model, baseboard_group, :baseboard, applied_settings)

          model.selection.clear
          model.selection.add(wall_one)
          regenerated_groups = BaseboardBuilder.build_from_selection(model, model.selection, applied_settings)
          active_room_baseboards = model.active_entities.grep(Sketchup::Group).select do |group|
            group.get_attribute(PLUGIN_ID, 'entity_type') == 'baseboard' &&
              GeometryBuilder.room_token(group) == room_token
          end
          baseboard_regenerated = regenerated_groups.length == 1 && active_room_baseboards.length == 1

          model.selection.clear
          model.selection.add(wall_one)
          selection_state = ParametricEditor.selection_state(model)
          parametric_selection_ok = selection_state[:available] &&
                                    selection_state[:entity_type] == 'wall' &&
                                    selection_state[:wall] &&
                                    selection_state[:wall][:openings].any? { |opening| opening[:kind] == 'door' }

          ParametricEditor.apply_wall_edits(
            model,
            model.selection,
            {
              'wall_thickness_cm' => 25,
              'wall_height_cm' => 350,
              'alignment' => 'center'
            }
          )
          updated_wall_one = GeometryBuilder.wall_info(wall_one)
          wall_parametric_edit_ok = updated_wall_one &&
                                    (updated_wall_one[:thickness] - 25.cm).abs <= 0.1.mm &&
                                    (updated_wall_one[:height] - 350.cm).abs <= 0.1.mm

          selection_state = ParametricEditor.selection_state(model)
          door_entry = selection_state[:wall][:openings].find { |opening| opening[:kind] == 'door' }
          ParametricEditor.apply_opening_edits(
            model,
            model.selection,
            {
              'id' => door_entry[:id],
              'opening_width_cm' => 100,
              'opening_height_cm' => 220,
              'center_distance_cm' => 180
            }
          )
          updated_door = GeometryBuilder.opening_records(wall_one).find { |opening| opening[:id] == door_entry[:id] }
          door_parametric_edit_ok = updated_door &&
                                    (updated_door[:opening_width] - 100.cm).abs <= 0.1.mm &&
                                    ((updated_door[:top_z] - updated_door[:bottom_z]) - 220.cm).abs <= 0.1.mm &&
                                    (updated_door[:center_distance] - 180.cm).abs <= 0.1.mm

          model.selection.clear
          model.selection.add(wall_two)
          selection_state = ParametricEditor.selection_state(model)
          window_entry = selection_state[:wall][:openings].find { |opening| opening[:kind] == 'window' }
          ParametricEditor.apply_opening_edits(
            model,
            model.selection,
            {
              'id' => window_entry[:id],
              'opening_width_cm' => 150,
              'opening_height_cm' => 130,
              'center_distance_cm' => 150,
              'bottom_height_cm' => 95
            }
          )
          updated_window = GeometryBuilder.opening_records(wall_two).find { |opening| opening[:id] == window_entry[:id] }
          window_parametric_edit_ok = updated_window &&
                                      (updated_window[:opening_width] - 150.cm).abs <= 0.1.mm &&
                                      ((updated_window[:top_z] - updated_window[:bottom_z]) - 130.cm).abs <= 0.1.mm &&
                                      (updated_window[:center_distance] - 150.cm).abs <= 0.1.mm &&
                                      (updated_window[:bottom_z] - 95.cm).abs <= 0.1.mm

          regenerated_floor = room_group(model, room_token, 'floor')
          regenerated_baseboard = room_group(model, room_token, 'baseboard')
          model.selection.clear
          model.selection.add(regenerated_floor) if regenerated_floor
          ParametricEditor.regenerate_selected_room(model, model.selection)
          regenerated_floor = room_group(model, room_token, 'floor')
          regenerated_baseboard = room_group(model, room_token, 'baseboard')
          regenerated_floor_bounds = regenerated_floor ? regenerated_floor.bounds : nil
          room_regeneration_ok = regenerated_floor_bounds &&
                                 regenerated_baseboard &&
                                 room_walls_match?(model, room_token, 25.cm, 350.cm) &&
                                 (regenerated_floor_bounds.min.x - 12.5.cm).abs <= 0.1.mm &&
                                 (regenerated_floor_bounds.max.x - 387.5.cm).abs <= 0.1.mm &&
                                 (regenerated_floor_bounds.min.y - 12.5.cm).abs <= 0.1.mm &&
                                 (regenerated_floor_bounds.max.y - 287.5.cm).abs <= 0.1.mm &&
                                 baseboard_segment_min_z(regenerated_baseboard) &&
                                 (baseboard_segment_min_z(regenerated_baseboard) - regenerated_floor_bounds.max.z).abs <= 0.1.mm
          layer_regeneration_ok = room_layers_match?(model, room_token)
          material_regeneration_ok = room_materials_match?(model, room_token, applied_settings)

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
          :room_tool_selected => room_tool_selected,
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
          :parametric_selection_ok => parametric_selection_ok,
          :wall_parametric_edit_ok => wall_parametric_edit_ok,
          :door_parametric_edit_ok => door_parametric_edit_ok,
          :window_parametric_edit_ok => window_parametric_edit_ok,
          :room_regeneration_ok => room_regeneration_ok,
          :wall_layer_ok => wall_layer_ok,
          :floor_layer_ok => floor_layer_ok,
          :baseboard_layer_ok => baseboard_layer_ok,
          :layer_regeneration_ok => layer_regeneration_ok,
          :wall_material_ok => wall_material_ok,
          :floor_material_ok => floor_material_ok,
          :baseboard_material_ok => baseboard_material_ok,
          :material_regeneration_ok => material_regeneration_ok,
          :room_generation_ok => room_generation_ok,
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

      def room_group(model, room_token, entity_type)
        model.active_entities.grep(Sketchup::Group).find do |group|
          group.get_attribute(PLUGIN_ID, 'entity_type') == entity_type &&
            GeometryBuilder.room_token(group) == room_token
        end
      end

      def room_walls_match?(model, room_token, thickness, height)
        walls = model.active_entities.grep(Sketchup::Group).select do |group|
          GeometryBuilder.wall_group?(group) && GeometryBuilder.room_token(group) == room_token
        end
        return false if walls.empty?

        walls.all? do |wall|
          info = GeometryBuilder.wall_info(wall)
          info &&
            (info[:thickness] - thickness).abs <= 0.1.mm &&
            (info[:height] - height).abs <= 0.1.mm
        end
      end

      def room_materials_match?(model, room_token, settings)
        walls = model.active_entities.grep(Sketchup::Group).select do |group|
          GeometryBuilder.wall_group?(group) && GeometryBuilder.room_token(group) == room_token
        end
        floor = room_group(model, room_token, 'floor')
        baseboard = room_group(model, room_token, 'baseboard')

        walls.any? &&
          walls.all? { |wall| material_applied?(model, wall, :wall, settings) } &&
          floor && material_applied?(model, floor, :floor, settings) &&
          baseboard && material_applied?(model, baseboard, :baseboard, settings) &&
          nested_group_materials_match?(model, baseboard, :baseboard, settings)
      end

      def room_layers_match?(model, room_token)
        walls = model.active_entities.grep(Sketchup::Group).select do |group|
          GeometryBuilder.wall_group?(group) && GeometryBuilder.room_token(group) == room_token
        end
        floor = room_group(model, room_token, 'floor')
        baseboard = room_group(model, room_token, 'baseboard')

        walls.any? &&
          walls.all? { |wall| layer_applied?(model, wall, :wall) } &&
          floor && layer_applied?(model, floor, :floor) &&
          baseboard && layer_applied?(model, baseboard, :baseboard) &&
          nested_groups_on_default_layer?(model, baseboard)
      end

      def layer_applied?(model, entity, kind)
        return false unless entity&.valid?

        layer = layer_for_kind(model, kind)
        entity.layer && layer && entity.layer.name == layer.name
      end

      def nested_groups_on_default_layer?(model, parent_group)
        return false unless parent_group&.valid?

        default_layer = model.layers['Layer0'] || model.layers[0]
        nested = parent_group.entities.grep(Sketchup::Group)
        return true if nested.empty?

        nested.all? do |group|
          group.layer && default_layer && group.layer.name == default_layer.name
        end
      end

      def material_applied?(model, entity, kind, settings)
        return false unless entity&.valid?

        material = material_for_kind(model, kind, settings)
        return false unless material

        entity_material = entity.material
        entity_material &&
          entity_material.name == material.name &&
          colors_match?(entity_material.color, material.color)
      end

      def nested_group_materials_match?(model, parent_group, kind, settings)
        return false unless parent_group&.valid?

        material = material_for_kind(model, kind, settings)
        return false unless material

        nested = parent_group.entities.grep(Sketchup::Group)
        return true if nested.empty?

        nested.all? do |group|
          group.material &&
            group.material.name == material.name &&
            colors_match?(group.material.color, material.color)
        end
      end

      def material_for_kind(model, kind, settings)
        config = MaterialManager::MATERIAL_TYPES[kind.to_sym]
        return nil unless config

        name = settings[config[:name_key]]
        model.materials[name]
      end

      def layer_for_kind(model, kind)
        name = LayerManager::LAYER_NAMES[kind.to_sym]
        name ? model.layers[name] : nil
      end

      def colors_match?(color_a, color_b)
        return false unless color_a && color_b

        color_a.red == color_b.red &&
          color_a.green == color_b.green &&
          color_a.blue == color_b.blue
      end
    end
  end
end
