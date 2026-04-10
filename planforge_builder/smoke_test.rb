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
        shared_proxy_ok = false
        room_reconciliation_ok = false
        metric_room_input_ok = false
        metric_room_label_ok = false
        wall_block_quantity_ok = false
        opening_block_quantity_ok = false
        block_quantity_warning_ok = false
        proxy_block_quantity_ok = false
        room_regeneration_quantity_ok = false
        wall_mortar_estimate_ok = false
        opening_mortar_estimate_ok = false
        selection_mortar_estimate_ok = false
        room_regeneration_mortar_ok = false
        selection_structure_estimate_ok = false
        wall_block_conversion_ok = false
        wall_block_selection_ok = false
        wall_block_regeneration_ok = false
        wall_block_removal_ok = false
        opening_block_conversion_ok = false
        wall_structure_generation_ok = false
        door_structure_generation_ok = false
        window_structure_generation_ok = false
        shared_junction_generation_ok = false
        structural_selection_ok = false
        wall_structure_regeneration_ok = false
        wall_structure_regeneration_stage1_ok = false
        wall_structure_regeneration_stage2_ok = false
        wall_structure_regeneration_stage3_ok = false
        bond_beam_course_alignment_ok = false
        bond_beam_top_closure_ok = false
        lintel_course_alignment_ok = false
        sill_course_alignment_ok = false
        lintel_absorption_ok = false
        sill_omission_ok = false
        connected_cluster_host_join_ok = false
        material_memorial_empty_guard_ok = false
        material_memorial_pdf_ok = false
        memorial_only = truthy?(payload['memorial_only'])

        metric_room_input_ok = (MetricUnits.parse_length('4,5', 'm') - 450.cm).abs <= 0.1.mm &&
                               (MetricUnits.parse_length('500 cm', 'm') - 500.cm).abs <= 0.1.mm &&
                               (MetricUnits.parse_length('2800mm', 'm') - 280.cm).abs <= 0.1.mm
        metric_room_label_ok = MetricUnits.format_meters(450.cm) == '4,50 m' &&
                               MetricUnits.meter_field_value(500.cm) == '5,00'

        begin
          Diagnostics.write('smoke_test phase: begin geometry setup')
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
          begin
            MaterialMemorialReport.build(model, Settings.to_h)
            material_memorial_empty_guard_ok = false
          rescue ArgumentError => error
            material_memorial_empty_guard_ok = error.message.include?('Nao ha paredes convertidas em blocos')
          end

          wall_height_m = applied_settings[:wall_height_cm].to_f / 100.0
          wall_thickness_m = applied_settings[:wall_thickness_cm].to_f / 100.0
          bond_beam_height_m = expected_modular_bond_beam_height(applied_settings[:wall_height_cm].to_f) / 100.0
          door_width_m = applied_settings[:door_width_cm].to_f / 100.0
          door_height_m = applied_settings[:door_height_cm].to_f / 100.0
          window_width_m = applied_settings[:window_width_cm].to_f / 100.0
          window_height_m = applied_settings[:window_height_cm].to_f / 100.0
          expected_plain_structure_volume = (2.0 * 0.19 * wall_thickness_m * wall_height_m) + (3.62 * wall_thickness_m * bond_beam_height_m)
          expected_full_wall_area = 4.0 * wall_height_m
          expected_side_wall_area = 3.0 * wall_height_m
          expected_door_area = door_width_m * door_height_m
          expected_window_area = window_width_m * window_height_m
          expected_full_wall_mortar = expected_mortar_estimate(expected_full_wall_area)
          expected_door_wall_mortar = expected_mortar_estimate(expected_full_wall_area - expected_door_area)
          expected_window_wall_mortar = expected_mortar_estimate(expected_side_wall_area - expected_window_area)
          wall_three_quantities = GeometryBuilder.wall_quantities(wall_three)
          wall_one_quantities = GeometryBuilder.wall_quantities(wall_one)
          wall_two_quantities = GeometryBuilder.wall_quantities(wall_two)
          wall_block_quantity_ok = wall_three_quantities &&
                                   (wall_three_quantities[:gross_area_m2] - expected_full_wall_area).abs <= 0.01 &&
                                   wall_three_quantities[:opening_area_m2].abs <= 0.01 &&
                                   (wall_three_quantities[:net_area_m2] - expected_full_wall_area).abs <= 0.01 &&
                                   wall_three_quantities[:block_count] == expected_block_count(expected_full_wall_area) &&
                                   wall_three.get_attribute(PLUGIN_ID, 'block_count').to_i == expected_block_count(expected_full_wall_area) &&
                                   wall_three.description.include?("#{expected_block_count(expected_full_wall_area)} un")
          opening_block_quantity_ok = wall_one_quantities &&
                                      (wall_one_quantities[:opening_area_m2] - expected_door_area).abs <= 0.01 &&
                                      (wall_one_quantities[:net_area_m2] - (expected_full_wall_area - expected_door_area)).abs <= 0.01 &&
                                      wall_one_quantities[:block_count] == expected_block_count(expected_full_wall_area - expected_door_area) &&
                                      wall_one.description.include?("#{expected_block_count(expected_full_wall_area - expected_door_area)} un") &&
                                      wall_two_quantities &&
                                      (wall_two_quantities[:opening_area_m2] - expected_window_area).abs <= 0.01 &&
                                      wall_two_quantities[:block_count] == expected_block_count(expected_side_wall_area - expected_window_area)
          wall_mortar_estimate_ok = wall_three_quantities &&
                                    mortar_matches?(wall_three_quantities, expected_full_wall_mortar) &&
                                    wall_three.get_attribute(PLUGIN_ID, 'mortar_mix') == GeometryBuilder::MORTAR_MIX &&
                                    approx_equal?(wall_three.get_attribute(PLUGIN_ID, 'mortar_volume_m3').to_f, expected_full_wall_mortar[:volume_m3], 0.0001) &&
                                    approx_equal?(wall_three.get_attribute(PLUGIN_ID, 'mortar_cement_kg').to_f, expected_full_wall_mortar[:cement_kg], 0.01) &&
                                    approx_equal?(wall_three.get_attribute(PLUGIN_ID, 'mortar_lime_kg').to_f, expected_full_wall_mortar[:lime_kg], 0.01) &&
                                    approx_equal?(wall_three.get_attribute(PLUGIN_ID, 'mortar_sand_m3').to_f, expected_full_wall_mortar[:sand_m3], 0.0001)
          opening_mortar_estimate_ok = wall_one_quantities &&
                                       mortar_matches?(wall_one_quantities, expected_door_wall_mortar) &&
                                       wall_two_quantities &&
                                       mortar_matches?(wall_two_quantities, expected_window_wall_mortar)
          model.selection.clear
          model.selection.add(wall_two)
          selection_state = ParametricEditor.selection_state(model)
          selection_structure_estimate_ok = selection_state[:available] &&
                                            selection_state[:wall] &&
                                            selection_state[:wall][:structure_estimate] &&
                                            selection_state[:wall][:structure_estimate][:column_count] == 2 &&
                                            selection_state[:wall][:structure_estimate][:lintel_count] == 1 &&
                                            selection_state[:wall][:structure_estimate][:sill_beam_count] == 1

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

          host_room = RoomBuilder.build_rect_room(
            model,
            Geom::Point3d.new(1400.cm, 50.cm, 0),
            400.cm,
            300.cm,
            applied_settings
          )
          attached_room = RoomBuilder.build_rect_room(
            model,
            Geom::Point3d.new(1500.cm, 350.cm, 0),
            200.cm,
            200.cm,
            applied_settings
          )
          host_snapshot = RoomRegenerator.room_snapshot(model, host_room[:room_token])
          attached_snapshot = RoomRegenerator.room_snapshot(model, attached_room[:room_token])
          host_top_wall = wall_by_sequence(host_snapshot[:walls], 2)
          attached_bottom_wall = wall_by_sequence(attached_snapshot[:walls], 0)
          attached_right_wall = wall_by_sequence(attached_snapshot[:walls], 1)
          attached_left_wall = wall_by_sequence(attached_snapshot[:walls], 3)
          shared_proxy_ok = host_top_wall &&
                            attached_bottom_wall &&
                            GeometryBuilder.physical_wall_group?(host_top_wall) &&
                            GeometryBuilder.proxy_wall?(attached_bottom_wall) &&
                            GeometryBuilder.shared_wall_id(attached_bottom_wall) == host_top_wall.persistent_id
          right_info = attached_right_wall ? GeometryBuilder.wall_info(attached_right_wall) : nil
          left_info = attached_left_wall ? GeometryBuilder.wall_info(attached_left_wall) : nil
          room_reconciliation_ok = shared_proxy_ok &&
                                   right_info &&
                                   left_info &&
                                   endpoint_matches_y?(right_info, 350.cm) &&
                                   endpoint_matches_y?(left_info, 350.cm)
          proxy_block_quantity_ok = attached_bottom_wall &&
                                    GeometryBuilder.wall_quantities(attached_bottom_wall).nil? &&
                                    attached_bottom_wall.get_attribute(PLUGIN_ID, 'block_count').nil? &&
                                    attached_bottom_wall.description.to_s.empty?

          room_token = GeometryBuilder.assign_room_metadata([wall_one, wall_two, wall_three, wall_four], [p1, p2, p3, p4, p1], applied_settings)

          wall_three_blocks = WallBlockBuilder.build_for_wall(model, wall_three, applied_settings, true)
          wall_one_blocks = block_group_for_wall(model, wall_one)
          wall_two_blocks = block_group_for_wall(model, wall_two)
          wall_four_blocks = block_group_for_wall(model, wall_four)
          room_junction_group = room_group(model, room_token, 'room_wall_structure_junctions')
          wall_three_structure = WallBlockBuilder.structure_estimate(wall_three)
          wall_three_units = block_units(wall_three_blocks)
          wall_block_conversion_ok = wall_three&.hidden? &&
                                     wall_one&.hidden? &&
                                     wall_two&.hidden? &&
                                     wall_four&.hidden? &&
                                     wall_three_blocks &&
                                     wall_three_blocks.valid? &&
                                     wall_one_blocks &&
                                     wall_two_blocks &&
                                     wall_four_blocks &&
                                     wall_three_blocks.get_attribute(PLUGIN_ID, 'source_wall_id').to_i == wall_three.persistent_id &&
                                     linked_block_group_count(model, wall_one) == 1 &&
                                     linked_block_group_count(model, wall_two) == 1 &&
                                     linked_block_group_count(model, wall_three) == 1 &&
                                     linked_block_group_count(model, wall_four) == 1 &&
                                     wall_three_units.any? &&
                                     wall_three_units.any? { |unit| unit.get_attribute(PLUGIN_ID, 'piece_kind') == 'full' } &&
                                     approx_equal?(first_bond_offset_for_course(wall_three_blocks, 0), 0.0, 0.01) &&
                                     approx_equal?(first_bond_offset_for_course(wall_three_blocks, 1), 20.0, 0.01) &&
                                     wall_three_units.any? { |unit| unit.is_a?(Sketchup::ComponentInstance) }
          Diagnostics.write('smoke_test phase: room conversion checks done')
          shared_junction_generation_ok = room_junction_group &&
                                          room_junction_group.valid? &&
                                          structural_piece_count(room_junction_group, 'junction_column') == 4 &&
                                          junction_piece_count_for_wall(room_junction_group, wall_three) == 2 &&
                                          junction_piece_count_for_wall(room_junction_group, wall_one) == 2
          wall_structure_generation_ok = wall_three_structure &&
                                         wall_three_structure[:column_count] == 2 &&
                                         approx_equal?(wall_three_structure[:bond_beam_length_m], 3.62, 0.01) &&
                                         wall_three_structure[:lintel_count].zero? &&
                                         wall_three_structure[:sill_beam_count].zero? &&
                                         approx_equal?(wall_three_structure[:total_concrete_volume_m3], expected_plain_structure_volume, 0.01) &&
                                         structural_piece_count(wall_three_blocks, 'column').zero? &&
                                         structural_piece_count(wall_three_blocks, 'bond_beam') == 1 &&
                                         structural_piece_count(wall_three_blocks, 'lintel').zero? &&
                                         structural_piece_count(wall_three_blocks, 'sill_beam').zero? &&
                                         no_block_structure_overlap?(wall_three_blocks) &&
                                         no_junction_structure_overlap?(room_junction_group, wall_three, wall_three_blocks)
          bond_beam_piece = first_structural_piece(wall_three_blocks, 'bond_beam')
          bond_beam_course_alignment_ok = piece_aligned_to_course_bottom?(bond_beam_piece, wall_three)
          bond_beam_top_closure_ok = piece_flush_to_wall_top?(bond_beam_piece, wall_three)

          door_record = GeometryBuilder.opening_records(wall_one).find { |opening| opening[:kind] == 'door' }
          wall_one_structure = WallBlockBuilder.structure_estimate(wall_one)
          opening_block_conversion_ok = wall_one&.hidden? &&
                                        wall_one_blocks &&
                                        wall_one_blocks.valid? &&
                                        block_units(wall_one_blocks).any? { |unit| unit.get_attribute(PLUGIN_ID, 'piece_kind') == 'cut' } &&
                                        opening_clear?(wall_one_blocks, door_record)
          door_structure_generation_ok = wall_one_structure &&
                                         wall_one_structure[:column_count] == 2 &&
                                         wall_one_structure[:lintel_count] == 1 &&
                                         wall_one_structure[:sill_beam_count].zero? &&
                                         structural_piece_count(wall_one_blocks, 'column').zero? &&
                                         structural_piece_count(wall_one_blocks, 'bond_beam') == 1 &&
                                         structural_piece_count(wall_one_blocks, 'lintel') == 1 &&
                                         structural_piece_count(wall_one_blocks, 'sill_beam').zero? &&
                                         no_block_structure_overlap?(wall_one_blocks) &&
                                         no_junction_structure_overlap?(room_junction_group, wall_one, wall_one_blocks)
          lintel_course_alignment_ok = piece_aligned_to_course_bottom?(first_structural_piece(wall_one_blocks, 'lintel'), wall_one)

          wall_two_structure = WallBlockBuilder.structure_estimate(wall_two)
          window_structure_generation_ok = wall_two&.hidden? &&
                                           wall_two_blocks &&
                                           wall_two_structure &&
                                           wall_two_structure[:column_count] == 2 &&
                                           wall_two_structure[:lintel_count] == 1 &&
                                           wall_two_structure[:sill_beam_count] == 1 &&
                                           structural_piece_count(wall_two_blocks, 'column').zero? &&
                                           structural_piece_count(wall_two_blocks, 'bond_beam') == 1 &&
                                           structural_piece_count(wall_two_blocks, 'lintel') == 1 &&
                                           structural_piece_count(wall_two_blocks, 'sill_beam') == 1 &&
                                           no_block_structure_overlap?(wall_two_blocks) &&
                                           no_junction_structure_overlap?(room_junction_group, wall_two, wall_two_blocks)
          sill_course_alignment_ok = piece_aligned_to_course_top?(first_structural_piece(wall_two_blocks, 'sill_beam'), wall_two)

          column_piece = first_junction_piece_for_wall(room_junction_group, wall_three)
          model.selection.clear
          model.selection.add(column_piece) if column_piece
          selection_state = ParametricEditor.selection_state(model)
          structural_selection_ok = column_piece &&
                                    selection_state[:available] &&
                                    selection_state[:entity_type] == 'wall' &&
                                    selection_state[:wall] &&
                                    selection_state[:wall][:structure_estimate] &&
                                    selection_state[:wall][:structure_estimate][:column_count] == 2 &&
                                    selection_state[:wall][:block_conversion] &&
                                    selection_state[:wall][:block_conversion][:has_block_conversion]

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
          model.selection.add(wall_one_blocks)
          regenerated_groups = BaseboardBuilder.build_from_selection(model, model.selection, applied_settings)
          active_room_baseboards = model.active_entities.grep(Sketchup::Group).select do |group|
            group.get_attribute(PLUGIN_ID, 'entity_type') == 'baseboard' &&
              GeometryBuilder.room_token(group) == room_token
          end
          baseboard_regenerated = regenerated_groups.length == 1 && active_room_baseboards.length == 1

          model.selection.clear
          model.selection.add(wall_one_blocks)
          selection_state = ParametricEditor.selection_state(model)
          wall_block_selection_ok = selection_state[:available] &&
                                    selection_state[:entity_type] == 'wall' &&
                                    selection_state[:wall] &&
                                    selection_state[:wall][:block_conversion] &&
                                    selection_state[:wall][:block_conversion][:has_block_conversion] &&
                                    selection_state[:wall][:block_conversion][:block_conversion_hidden_host]
          parametric_selection_ok = wall_block_selection_ok &&
                                    selection_state[:wall][:block_estimate] &&
                                    selection_state[:wall][:block_estimate][:block_count] == expected_block_count(expected_full_wall_area - expected_door_area) &&
                                    selection_state[:wall][:structure_estimate] &&
                                    selection_state[:wall][:structure_estimate][:lintel_count] == 1 &&
                                    selection_state[:wall][:openings].any? { |opening| opening[:kind] == 'door' }
          selection_mortar_estimate_ok = selection_state[:wall][:mortar_estimate] &&
                                         selection_state[:wall][:mortar_estimate][:mix] == GeometryBuilder::MORTAR_MIX &&
                                         approx_equal?(selection_state[:wall][:mortar_estimate][:volume_m3].to_f, expected_door_wall_mortar[:volume_m3], 0.001) &&
                                         approx_equal?(selection_state[:wall][:mortar_estimate][:cement_kg].to_f, expected_door_wall_mortar[:cement_kg], 0.1) &&
                                         approx_equal?(selection_state[:wall][:mortar_estimate][:lime_kg].to_f, expected_door_wall_mortar[:lime_kg], 0.1) &&
                                         approx_equal?(selection_state[:wall][:mortar_estimate][:sand_m3].to_f, expected_door_wall_mortar[:sand_m3], 0.001)

          ParametricEditor.apply_wall_edits(
            model,
            model.selection,
            {
              'wall_thickness_cm' => 25,
              'wall_height_cm' => 350,
              'alignment' => 'center'
            }
          )
          refreshed_room = RoomRegenerator.room_snapshot(model, room_token)
          wall_one = wall_by_sequence(refreshed_room[:walls], 0) || wall_with_opening_kind(refreshed_room[:walls], 'door') || room_wall_with_opening(model, room_token, 'door') || wall_with_opening_kind_in_model(model, 'door') || selected_wall_from_model(model)
          wall_two = wall_by_sequence(refreshed_room[:walls], 1) || wall_with_opening_kind(refreshed_room[:walls], 'window') || room_wall_with_opening(model, room_token, 'window') || wall_with_opening_kind_in_model(model, 'window')
          wall_three = wall_by_sequence(refreshed_room[:walls], 2) || room_wall_by_sequence(model, room_token, 2)
          wall_four = wall_by_sequence(refreshed_room[:walls], 3) || room_wall_by_sequence(model, room_token, 3)
          updated_wall_one = GeometryBuilder.wall_info(wall_one)
          wall_one_blocks = block_group_for_wall(model, wall_one)
          wall_parametric_edit_ok = updated_wall_one &&
                                    (updated_wall_one[:thickness] - 25.cm).abs <= 0.1.mm &&
                                    (updated_wall_one[:height] - 350.cm).abs <= 0.1.mm
          wall_block_regeneration_ok = wall_parametric_edit_ok &&
                                       wall_one&.hidden? &&
                                       linked_block_group_count(model, wall_one) == 1 &&
                                       wall_one_blocks &&
                                       approx_equal?(first_bond_offset_for_course(wall_one_blocks, 0), 0.0, 0.01) &&
                                       approx_equal?(first_bond_offset_for_course(wall_one_blocks, 1), 20.0, 0.01)
          room_junction_group = room_group(model, room_token, 'room_wall_structure_junctions')
          wall_one_structure = WallBlockBuilder.structure_estimate(wall_one)
          wall_structure_regeneration_stage1_ok = wall_parametric_edit_ok &&
                                                  wall_one_structure &&
                                                  wall_one_structure[:column_count] == 2 &&
                                                  wall_one_structure[:lintel_count] == 1 &&
                                                  room_junction_group &&
                                                  structural_piece_count(room_junction_group, 'junction_column') == 4 &&
                                                  structural_piece_count(wall_one_blocks, 'column').zero? &&
                                                  structural_piece_count(wall_one_blocks, 'bond_beam') == 1 &&
                                                  structural_piece_count(wall_one_blocks, 'lintel') == 1 &&
                                                  no_block_structure_overlap?(wall_one_blocks) &&
                                                  no_junction_structure_overlap?(room_junction_group, wall_one, wall_one_blocks)
          wall_structure_regeneration_ok = wall_structure_regeneration_stage1_ok

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
          refreshed_room = RoomRegenerator.room_snapshot(model, room_token)
          wall_one = wall_by_sequence(refreshed_room[:walls], 0) || wall_with_opening_kind(refreshed_room[:walls], 'door') || room_wall_with_opening(model, room_token, 'door') || wall_with_opening_kind_in_model(model, 'door') || selected_wall_from_model(model)
          wall_two = wall_by_sequence(refreshed_room[:walls], 1) || wall_with_opening_kind(refreshed_room[:walls], 'window') || room_wall_with_opening(model, room_token, 'window') || wall_with_opening_kind_in_model(model, 'window')
          wall_three = wall_by_sequence(refreshed_room[:walls], 2) || room_wall_by_sequence(model, room_token, 2)
          wall_four = wall_by_sequence(refreshed_room[:walls], 3) || room_wall_by_sequence(model, room_token, 3)
          updated_door = GeometryBuilder.opening_records(wall_one).find { |opening| opening[:id] == door_entry[:id] }
          wall_one_blocks = block_group_for_wall(model, wall_one)
          door_parametric_edit_ok = updated_door &&
                                    (updated_door[:opening_width] - 100.cm).abs <= 0.1.mm &&
                                    ((updated_door[:top_z] - updated_door[:bottom_z]) - 220.cm).abs <= 0.1.mm &&
                                    (updated_door[:center_distance] - 180.cm).abs <= 0.1.mm
          wall_block_regeneration_ok &&= wall_one&.hidden? &&
                                        linked_block_group_count(model, wall_one) == 1 &&
                                        wall_one_blocks &&
                                        block_units(wall_one_blocks).any? { |unit| unit.get_attribute(PLUGIN_ID, 'piece_kind') == 'cut' } &&
                                        opening_clear?(wall_one_blocks, updated_door)
          wall_one_structure = WallBlockBuilder.structure_estimate(wall_one)
          wall_structure_regeneration_stage2_ok = wall_one_structure &&
                                                  wall_one_structure[:lintel_count] == 1 &&
                                                  approx_equal?(wall_one_structure[:lintel_length_m], 1.40, 0.01) &&
                                                  structural_piece_count(wall_one_blocks, 'lintel') == 1 &&
                                                  no_block_structure_overlap?(wall_one_blocks) &&
                                                  no_junction_structure_overlap?(room_junction_group, wall_one, wall_one_blocks)
          wall_structure_regeneration_ok &&= wall_structure_regeneration_stage2_ok
          warning_quantities = GeometryBuilder.wall_quantities(wall_one)
          block_quantity_warning_ok = warning_quantities &&
                                      (warning_quantities[:gross_area_m2] - 14.0).abs <= 0.01 &&
                                      (warning_quantities[:opening_area_m2] - 2.2).abs <= 0.01 &&
                                      (warning_quantities[:net_area_m2] - 11.8).abs <= 0.01 &&
                                      warning_quantities[:block_count] == 148 &&
                                      warning_quantities[:block_warning].to_s.include?('25.00 cm') &&
                                      wall_one.get_attribute(PLUGIN_ID, 'block_count').to_i == 148 &&
                                      wall_one.get_attribute(PLUGIN_ID, 'block_warning').to_s.include?('25.00 cm') &&
          wall_one.description.include?('148 un') &&
                                      wall_one.description.include?('Aviso:')

          model.selection.clear
          model.selection.add(wall_two) if wall_two
          selection_state = ParametricEditor.selection_state(model)
          window_entry = selection_state[:wall] ? selection_state[:wall][:openings].find { |opening| opening[:kind] == 'window' } : nil
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
          ) if window_entry
          refreshed_room = RoomRegenerator.room_snapshot(model, room_token)
          wall_one = wall_by_sequence(refreshed_room[:walls], 0) || wall_with_opening_kind(refreshed_room[:walls], 'door') || room_wall_with_opening(model, room_token, 'door') || wall_with_opening_kind_in_model(model, 'door')
          wall_two = wall_by_sequence(refreshed_room[:walls], 1) || wall_with_opening_kind(refreshed_room[:walls], 'window') || room_wall_with_opening(model, room_token, 'window') || wall_with_opening_kind_in_model(model, 'window') || selected_wall_from_model(model)
          wall_three = wall_by_sequence(refreshed_room[:walls], 2) || room_wall_by_sequence(model, room_token, 2)
          wall_four = wall_by_sequence(refreshed_room[:walls], 3) || room_wall_by_sequence(model, room_token, 3)
          updated_window = GeometryBuilder.opening_records(wall_two).find { |opening| opening[:id] == window_entry[:id] }
          window_parametric_edit_ok = updated_window &&
                                      (updated_window[:opening_width] - 150.cm).abs <= 0.1.mm &&
                                      ((updated_window[:top_z] - updated_window[:bottom_z]) - 130.cm).abs <= 0.1.mm &&
                                      (updated_window[:center_distance] - 150.cm).abs <= 0.1.mm &&
                                      (updated_window[:bottom_z] - 95.cm).abs <= 0.1.mm

          regenerated_floor = room_group(model, room_token, 'floor')
          regenerated_baseboard = room_group(model, room_token, 'baseboard')
          wall_one_blocks = block_group_for_wall(model, wall_one)
          model.selection.clear
          model.selection.add(wall_one_blocks) if wall_one_blocks&.valid?
          ParametricEditor.regenerate_selected_room(model, model.selection)
          refreshed_room = RoomRegenerator.room_snapshot(model, room_token)
          wall_one = wall_by_sequence(refreshed_room[:walls], 0) || wall_with_opening_kind(refreshed_room[:walls], 'door') || room_wall_with_opening(model, room_token, 'door') || wall_with_opening_kind_in_model(model, 'door') || selected_wall_from_model(model)
          wall_two = wall_by_sequence(refreshed_room[:walls], 1) || wall_with_opening_kind(refreshed_room[:walls], 'window') || room_wall_with_opening(model, room_token, 'window') || wall_with_opening_kind_in_model(model, 'window')
          wall_three = wall_by_sequence(refreshed_room[:walls], 2) || room_wall_by_sequence(model, room_token, 2)
          wall_four = wall_by_sequence(refreshed_room[:walls], 3) || room_wall_by_sequence(model, room_token, 3)
          regenerated_floor = room_group(model, room_token, 'floor')
          regenerated_baseboard = room_group(model, room_token, 'baseboard')
          regenerated_floor_bounds = regenerated_floor ? regenerated_floor.bounds : nil
          wall_one_blocks = block_group_for_wall(model, wall_one)
          room_regeneration_ok = regenerated_floor_bounds &&
                                 regenerated_baseboard &&
                                 room_walls_match?(model, room_token, 25.cm, 350.cm) &&
                                 (regenerated_floor_bounds.min.x - 12.5.cm).abs <= 0.1.mm &&
                                 (regenerated_floor_bounds.max.x - 387.5.cm).abs <= 0.1.mm &&
                                 (regenerated_floor_bounds.min.y - 12.5.cm).abs <= 0.1.mm &&
                                 (regenerated_floor_bounds.max.y - 287.5.cm).abs <= 0.1.mm &&
                                 baseboard_segment_min_z(regenerated_baseboard) &&
                                 (baseboard_segment_min_z(regenerated_baseboard) - regenerated_floor_bounds.max.z).abs <= 0.1.mm &&
                                 wall_one&.hidden? &&
                                 wall_one_blocks &&
                                 linked_block_group_count(model, wall_one) == 1 &&
                                 opening_clear?(wall_one_blocks, GeometryBuilder.opening_records(wall_one).find { |opening| opening[:kind] == 'door' })
          regenerated_quantities = GeometryBuilder.wall_quantities(wall_one)
          room_regeneration_quantity_ok = regenerated_quantities &&
                                          regenerated_quantities[:block_count] == 148 &&
                                          regenerated_quantities[:block_warning].to_s.include?('25.00 cm') &&
                                          (wall_one.get_attribute(PLUGIN_ID, 'net_area_m2').to_f - 11.8).abs <= 0.01
          room_regeneration_mortar_ok = regenerated_quantities &&
                                        mortar_matches?(regenerated_quantities, expected_mortar_estimate(11.8)) &&
                                        approx_equal?(wall_one.get_attribute(PLUGIN_ID, 'mortar_volume_m3').to_f, expected_mortar_estimate(11.8)[:volume_m3], 0.0001)
          wall_one_structure = WallBlockBuilder.structure_estimate(wall_one)
          room_junction_group = room_group(model, room_token, 'room_wall_structure_junctions')
          wall_structure_regeneration_stage3_ok = wall_one_structure &&
                                                  wall_one_structure[:column_count] == 2 &&
                                                  wall_one_structure[:lintel_count] == 1 &&
                                                  room_junction_group &&
                                                  structural_piece_count(room_junction_group, 'junction_column') == 4 &&
                                                  structural_piece_count(wall_one_blocks, 'column').zero? &&
                                                  structural_piece_count(wall_one_blocks, 'bond_beam') == 1 &&
                                                  structural_piece_count(wall_one_blocks, 'lintel') == 1 &&
                                                  linked_block_group_count(model, wall_one) == 1 &&
                                                  no_block_structure_overlap?(wall_one_blocks) &&
                                                  no_junction_structure_overlap?(room_junction_group, wall_one, wall_one_blocks)
          wall_structure_regeneration_ok &&= wall_structure_regeneration_stage3_ok
          layer_regeneration_ok = room_layers_match?(model, room_token)
          material_regeneration_ok = room_materials_match?(model, room_token, applied_settings)

          high_window_start = Geom::Point3d.new(2200.cm, 0, 0)
          high_window_end = Geom::Point3d.new(2500.cm, 0, 0)
          high_window_wall = GeometryBuilder.build_wall(model, high_window_start, high_window_end, applied_settings)
          GeometryBuilder.rebuild_wall_with_openings(
            high_window_wall,
            high_window_start,
            high_window_end,
            applied_settings,
            nil,
            nil,
            [
              {
                :id => 'window-high',
                :kind => 'window',
                :center_distance => 150.cm,
                :opening_width => 120.cm,
                :bottom_z => 140.cm,
                :top_z => 290.cm
              }
            ]
          )
          high_window_blocks = WallBlockBuilder.build_for_wall(model, high_window_wall, applied_settings, true)
          high_window_structure = WallBlockBuilder.structure_estimate(high_window_wall)
          lintel_absorption_ok = high_window_blocks &&
                                 high_window_structure &&
                                 high_window_structure[:lintel_count].zero? &&
                                 high_window_structure[:sill_beam_count] == 1 &&
                                 high_window_structure[:warning_text].include?('verga absorvida pela cinta superior') &&
                                 structural_piece_count(high_window_blocks, 'lintel').zero? &&
                                 structural_piece_count(high_window_blocks, 'sill_beam') == 1

          low_window_start = Geom::Point3d.new(2200.cm, 400.cm, 0)
          low_window_end = Geom::Point3d.new(2500.cm, 400.cm, 0)
          low_window_wall = GeometryBuilder.build_wall(model, low_window_start, low_window_end, applied_settings)
          GeometryBuilder.rebuild_wall_with_openings(
            low_window_wall,
            low_window_start,
            low_window_end,
            applied_settings,
            nil,
            nil,
            [
              {
                :id => 'window-low',
                :kind => 'window',
                :center_distance => 150.cm,
                :opening_width => 120.cm,
                :bottom_z => 10.cm,
                :top_z => 130.cm
              }
            ]
          )
          low_window_blocks = WallBlockBuilder.build_for_wall(model, low_window_wall, applied_settings, true)
          low_window_structure = WallBlockBuilder.structure_estimate(low_window_wall)
          sill_omission_ok = low_window_blocks &&
                             low_window_structure &&
                             low_window_structure[:lintel_count] == 1 &&
                             low_window_structure[:sill_beam_count].zero? &&
                             low_window_structure[:warning_text].include?('contra-verga omitida por falta de espaco abaixo do peitoril') &&
                             structural_piece_count(low_window_blocks, 'lintel') == 1 &&
                             structural_piece_count(low_window_blocks, 'sill_beam').zero?
          Diagnostics.write('smoke_test phase: standalone opening checks done')

          if memorial_only
            material_memorial_pdf_ok = run_material_memorial_export_check(
              model,
              requested_settings,
              6,
              4,
              2
            )
          else

            cluster_start = Geom::Point3d.new(2800.cm, 0, 0)
            cluster_corner = Geom::Point3d.new(3100.cm, 0, 0)
            cluster_end = Geom::Point3d.new(3100.cm, 250.cm, 0)
            cluster_wall_one = GeometryBuilder.build_wall(model, cluster_start, cluster_corner, applied_settings)
            cluster_wall_two = GeometryBuilder.build_wall(model, cluster_corner, cluster_end, applied_settings)
            GeometryBuilder.cut_door_opening(cluster_wall_one, Geom::Point3d.new(2950.cm, 10.cm, 100.cm), applied_settings)
            WallBlockBuilder.build_for_wall(model, cluster_wall_one, applied_settings, true)
            cluster_scope_key = cluster_wall_one.get_attribute(PLUGIN_ID, 'conversion_scope_key').to_s
            cluster_junction_group = model.active_entities.grep(Sketchup::Group).find do |group|
              group.get_attribute(PLUGIN_ID, 'entity_type') == 'wall_structure_junctions' &&
                group.get_attribute(PLUGIN_ID, 'conversion_scope_key').to_s == cluster_scope_key
            end
            cluster_junction_generated = cluster_junction_group && cluster_junction_group.valid?
            Diagnostics.write('smoke_test phase: connected cluster conversion done')
            material_memorial_pdf_ok = run_material_memorial_export_check(
              model,
              requested_settings,
              8,
              4,
              4
            )
            WallBlockBuilder.remove_for_wall(model, cluster_wall_one)
            remaining_cluster_junction_group = model.active_entities.grep(Sketchup::Group).find do |group|
              group.get_attribute(PLUGIN_ID, 'entity_type') == 'wall_structure_junctions' &&
                group.get_attribute(PLUGIN_ID, 'conversion_scope_key').to_s == cluster_scope_key
            end
            connected_cluster_host_join_ok = cluster_wall_one &&
                                             cluster_wall_two &&
                                             cluster_junction_generated &&
                                             !cluster_wall_one.hidden? &&
                                             !cluster_wall_two.hidden? &&
                                             linked_block_group_count(model, cluster_wall_one).zero? &&
                                             linked_block_group_count(model, cluster_wall_two).zero? &&
                                             remaining_cluster_junction_group.nil? &&
                                             GeometryBuilder.opening_records(cluster_wall_one).any? { |opening| opening[:kind] == 'door' } &&
                                             walls_share_joined_edge?(cluster_wall_one, cluster_wall_two)
            Diagnostics.write('smoke_test phase: connected cluster removal done')
          end

          WallBlockBuilder.remove_for_wall(model, wall_three)
          room_junction_group = room_group(model, room_token, 'room_wall_structure_junctions')
          wall_block_removal_ok = wall_one && !wall_one.hidden? &&
                                  wall_two && !wall_two.hidden? &&
                                  wall_three && !wall_three.hidden? &&
                                  wall_four && !wall_four.hidden? &&
                                  linked_block_group_count(model, wall_one).zero? &&
                                  linked_block_group_count(model, wall_two).zero? &&
                                  linked_block_group_count(model, wall_three).zero? &&
                                  linked_block_group_count(model, wall_four).zero? &&
                                  room_junction_group.nil?
          Diagnostics.write('smoke_test phase: room removal done')

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
          :shared_proxy_ok => shared_proxy_ok,
          :room_reconciliation_ok => room_reconciliation_ok,
          :metric_room_input_ok => metric_room_input_ok,
          :metric_room_label_ok => metric_room_label_ok,
          :wall_block_quantity_ok => wall_block_quantity_ok,
          :opening_block_quantity_ok => opening_block_quantity_ok,
          :block_quantity_warning_ok => block_quantity_warning_ok,
          :proxy_block_quantity_ok => proxy_block_quantity_ok,
          :room_regeneration_quantity_ok => room_regeneration_quantity_ok,
          :wall_mortar_estimate_ok => wall_mortar_estimate_ok,
          :opening_mortar_estimate_ok => opening_mortar_estimate_ok,
          :selection_mortar_estimate_ok => selection_mortar_estimate_ok,
          :room_regeneration_mortar_ok => room_regeneration_mortar_ok,
          :selection_structure_estimate_ok => selection_structure_estimate_ok,
          :wall_block_conversion_ok => wall_block_conversion_ok,
          :wall_block_selection_ok => wall_block_selection_ok,
          :wall_block_regeneration_ok => wall_block_regeneration_ok,
          :wall_block_removal_ok => wall_block_removal_ok,
          :opening_block_conversion_ok => opening_block_conversion_ok,
          :wall_structure_generation_ok => wall_structure_generation_ok,
          :door_structure_generation_ok => door_structure_generation_ok,
          :window_structure_generation_ok => window_structure_generation_ok,
          :shared_junction_generation_ok => shared_junction_generation_ok,
          :structural_selection_ok => structural_selection_ok,
          :wall_structure_regeneration_ok => wall_structure_regeneration_ok,
          :wall_structure_regeneration_stage1_ok => wall_structure_regeneration_stage1_ok,
          :wall_structure_regeneration_stage2_ok => wall_structure_regeneration_stage2_ok,
          :wall_structure_regeneration_stage3_ok => wall_structure_regeneration_stage3_ok,
          :bond_beam_course_alignment_ok => bond_beam_course_alignment_ok,
          :bond_beam_top_closure_ok => bond_beam_top_closure_ok,
          :lintel_course_alignment_ok => lintel_course_alignment_ok,
          :sill_course_alignment_ok => sill_course_alignment_ok,
          :lintel_absorption_ok => lintel_absorption_ok,
          :sill_omission_ok => sill_omission_ok,
          :connected_cluster_host_join_ok => connected_cluster_host_join_ok,
          :material_memorial_empty_guard_ok => material_memorial_empty_guard_ok,
          :material_memorial_pdf_ok => material_memorial_pdf_ok,
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

      def run_material_memorial_export_check(model, requested_settings, expected_wall_count, expected_room_wall_count, expected_standalone_wall_count)
        memorial_pdf_path = File.join(ENV['TEMP'] || ROOT, 'planforge_builder_material_memorial_test.pdf')
        File.delete(memorial_pdf_path) if File.exist?(memorial_pdf_path)
        Diagnostics.write('smoke_test memorial: building report')
        memorial_report = MaterialMemorialReport.build(model, Settings.update(
          requested_settings.merge(
            :memorial_project_name => 'Casa Teste',
            :memorial_client_name => 'Cliente Smoke',
            :memorial_site_name => 'Lote 01',
            :memorial_responsible_name => 'Engenheiro Teste',
            :memorial_responsible_registry => 'CREA 123456',
            :memorial_notes => 'Emitido automaticamente pelo smoke test.'
          )
        ))
        Diagnostics.write('smoke_test memorial: writing pdf')
        MaterialMemorialPdf.write(memorial_report, memorial_pdf_path)
        Diagnostics.write('smoke_test memorial: reading pdf')
        memorial_pdf_binary = File.binread(memorial_pdf_path)
        room_group_entry = memorial_report[:groups].find { |group| group[:label].start_with?('Comodo ') }
        standalone_group_entry = memorial_report[:groups].find { |group| group[:label] == 'Paredes convertidas avulsas' }
        File.exist?(memorial_pdf_path) &&
          File.size(memorial_pdf_path) > 1500 &&
          memorial_report[:summary][:wall_count] == expected_wall_count &&
          room_group_entry &&
          room_group_entry[:wall_count] == expected_room_wall_count &&
          standalone_group_entry &&
          standalone_group_entry[:wall_count] == expected_standalone_wall_count &&
          !memorial_pdf_binary.empty?
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

      def walls_share_joined_edge?(wall_one, wall_two)
        footprint_one = wall_footprint_points(wall_one)
        footprint_two = wall_footprint_points(wall_two)
        return false if footprint_one.length < 4 || footprint_two.length < 4

        shared_points = footprint_one.count do |point|
          footprint_two.any? { |candidate| candidate.distance(point) <= 0.1.mm }
        end
        shared_points >= 2
      end

      def wall_footprint_points(group)
        return [] unless group&.valid?

        min_z = group.bounds.min.z
        face = group.entities.grep(Sketchup::Face).select do |candidate|
          candidate.normal.z.abs >= 0.99 &&
            candidate.vertices.all? { |vertex| (world_point(group, vertex.position).z - min_z).abs <= 0.1.mm }
        end.max_by(&:area)
        return [] unless face

        face.outer_loop.vertices.map { |vertex| world_point(group, vertex.position) }
      end

      def world_point(group, local_point)
        group.transformation * local_point
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

      def block_group_for_wall(model, wall)
        WallBlockBuilder.block_group_for_wall(model, wall)
      end

      def linked_block_group_count(model, wall)
        WallBlockBuilder.block_groups_for_wall(model, wall).count(&:valid?)
      end

      def block_units(group)
        return [] unless group&.valid?

        generated_entities(group).select do |entity|
          entity.get_attribute(PLUGIN_ID, 'entity_type') == 'wall_block_unit'
        end
      end

      def structural_pieces(group)
        return [] unless group&.valid?

        generated_entities(group).select do |entity|
          entity.get_attribute(PLUGIN_ID, 'entity_type') == 'wall_structural_piece'
        end
      end

      def structural_piece_count(group, kind)
        structural_pieces(group).count do |entity|
          entity.get_attribute(PLUGIN_ID, 'structural_kind').to_s == kind.to_s
        end
      end

      def first_structural_piece(group, kind)
        structural_pieces(group).find do |entity|
          entity.get_attribute(PLUGIN_ID, 'structural_kind').to_s == kind.to_s
        end
      end

      def junction_pieces_for_wall(group, wall)
        return [] unless group&.valid? && wall&.valid?

        structural_pieces(group).select do |entity|
          next false unless entity.get_attribute(PLUGIN_ID, 'structural_kind').to_s == 'junction_column'

          connected_wall_ids(entity).include?(wall.persistent_id)
        end
      end

      def junction_piece_count_for_wall(group, wall)
        junction_pieces_for_wall(group, wall).length
      end

      def first_junction_piece_for_wall(group, wall)
        junction_pieces_for_wall(group, wall).first
      end

      def no_junction_structure_overlap?(junction_group, wall, block_group)
        pieces = junction_pieces_for_wall(junction_group, wall)
        units = block_units(block_group)
        return false if pieces.empty? || units.empty?

        pieces.none? do |piece|
          units.any? { |unit| bounds_overlap?(piece.bounds, unit.bounds) }
        end
      end

      def no_block_structure_overlap?(group)
        pieces = structural_pieces(group)
        units = block_units(group)
        return false if pieces.empty? || units.empty?

        pieces.none? do |piece|
          units.any? { |unit| bounds_overlap?(piece.bounds, unit.bounds) }
        end
      end

      def generated_entities(group)
        return [] unless group&.valid?

        group.entities.each_with_object([]) do |entity, result|
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

          result << entity
          result.concat(generated_entities(entity)) if entity.is_a?(Sketchup::Group)
        end
      end

      def bounds_overlap?(bounds_a, bounds_b)
        overlap_on_axis?(bounds_a.min.x, bounds_a.max.x, bounds_b.min.x, bounds_b.max.x) &&
          overlap_on_axis?(bounds_a.min.y, bounds_a.max.y, bounds_b.min.y, bounds_b.max.y) &&
          overlap_on_axis?(bounds_a.min.z, bounds_a.max.z, bounds_b.min.z, bounds_b.max.z)
      end

      def overlap_on_axis?(min_a, max_a, min_b, max_b)
        max_a > (min_b + 0.1.mm) && max_b > (min_a + 0.1.mm)
      end

      def connected_wall_ids(entity)
        JSON.parse(entity.get_attribute(PLUGIN_ID, 'connected_wall_ids').to_s).map(&:to_i)
      rescue StandardError
        []
      end

      def first_bond_offset_for_course(group, course_index)
        units = block_units(group).select do |entity|
          entity.get_attribute(PLUGIN_ID, 'course_index').to_i == course_index
        end
        first = units.min_by { |entity| entity.get_attribute(PLUGIN_ID, 'piece_start_cm').to_f }
        first ? first.get_attribute(PLUGIN_ID, 'bond_offset_cm').to_f : nil
      end

      def piece_aligned_to_course_bottom?(piece, wall)
        return false unless piece&.valid? && wall&.valid?

        relative = (piece.bounds.min.z - GeometryBuilder.wall_info(wall)[:base_z].to_f) / 1.cm.to_f
        ((relative % 20.0).round(2)).abs <= 0.01
      end

      def piece_aligned_to_course_top?(piece, wall)
        return false unless piece&.valid? && wall&.valid?

        relative = (piece.bounds.max.z - GeometryBuilder.wall_info(wall)[:base_z].to_f) / 1.cm.to_f
        (((relative - 19.0) % 20.0).round(2)).abs <= 0.01
      end

      def piece_flush_to_wall_top?(piece, wall)
        return false unless piece&.valid? && wall&.valid?

        wall_info = GeometryBuilder.wall_info(wall)
        approx_equal?(piece.bounds.max.z, wall_info[:base_z].to_f + wall_info[:height].to_f, 0.1.mm)
      end

      def opening_clear?(group, opening)
        return false unless group&.valid? && opening

        opening_start = (opening[:center_distance].to_f - (opening[:opening_width].to_f / 2.0)) / 1.cm.to_f
        opening_end = (opening[:center_distance].to_f + (opening[:opening_width].to_f / 2.0)) / 1.cm.to_f
        opening_courses = block_units(group).select do |entity|
          bounds = entity.bounds
          opening[:bottom_z].to_f < (bounds.max.z - 0.1.mm) && opening[:top_z].to_f > (bounds.min.z + 0.1.mm)
        end

        opening_courses.none? do |entity|
          piece_start = entity.get_attribute(PLUGIN_ID, 'piece_start_cm').to_f
          piece_end = entity.get_attribute(PLUGIN_ID, 'piece_end_cm').to_f
          piece_end > (opening_start + 0.01) && piece_start < (opening_end - 0.01)
        end
      end

      def wall_by_sequence(walls, sequence)
        Array(walls).find do |group|
          group.get_attribute(PLUGIN_ID, 'room_sequence', -1).to_i == sequence
        end
      end

      def wall_with_opening_kind(walls, kind)
        Array(walls).find do |group|
          GeometryBuilder.opening_records(group).any? { |opening| opening[:kind].to_s == kind.to_s }
        end
      end

      def room_wall_by_sequence(model, room_token, sequence)
        model.active_entities.grep(Sketchup::Group).find do |group|
          GeometryBuilder.wall_group?(group) &&
            GeometryBuilder.room_token(group) == room_token &&
            group.get_attribute(PLUGIN_ID, 'room_sequence', -1).to_i == sequence
        end
      end

      def room_wall_with_opening(model, room_token, kind)
        model.active_entities.grep(Sketchup::Group).find do |group|
          GeometryBuilder.wall_group?(group) &&
            GeometryBuilder.room_token(group) == room_token &&
            GeometryBuilder.opening_records(group).any? { |opening| opening[:kind].to_s == kind.to_s }
        end
      end

      def wall_with_opening_kind_in_model(model, kind)
        model.active_entities.grep(Sketchup::Group).find do |group|
          GeometryBuilder.wall_group?(group) &&
            GeometryBuilder.opening_records(group).any? { |opening| opening[:kind].to_s == kind.to_s }
        end
      end

      def selected_wall_from_model(model)
        model.selection.to_a.each do |entity|
          wall = WallBlockBuilder.host_wall_for_entity(model, entity)
          return wall if GeometryBuilder.wall_group?(wall)
        end

        nil
      end

      def endpoint_matches_y?(wall_info, expected_y)
        [wall_info[:start_point], wall_info[:end_point]].any? do |point|
          (point.y - expected_y).abs <= 0.1.mm
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

      def mortar_matches?(estimate, expected)
        estimate &&
          estimate[:mortar_mix] == GeometryBuilder::MORTAR_MIX &&
          approx_equal?(estimate[:mortar_volume_m3].to_f, expected[:volume_m3], 0.0001) &&
          approx_equal?(estimate[:mortar_cement_kg].to_f, expected[:cement_kg], 0.01) &&
          approx_equal?(estimate[:mortar_lime_kg].to_f, expected[:lime_kg], 0.01) &&
          approx_equal?(estimate[:mortar_sand_m3].to_f, expected[:sand_m3], 0.0001)
      end

      def expected_mortar_estimate(area_m2)
        volume_m3 = area_m2.to_f * GeometryBuilder::MORTAR_CONSUMPTION_M3_PER_M2

        {
          :volume_m3 => volume_m3,
          :cement_kg => volume_m3 * GeometryBuilder::MORTAR_CEMENT_KG_PER_M3,
          :lime_kg => volume_m3 * GeometryBuilder::MORTAR_LIME_KG_PER_M3,
          :sand_m3 => volume_m3 * GeometryBuilder::MORTAR_SAND_M3_PER_M3
        }
      end

      def approx_equal?(actual, expected, tolerance)
        (actual.to_f - expected.to_f).abs <= tolerance
      end

      def expected_modular_bond_beam_height(wall_height_cm)
        desired_bottom_cm = wall_height_cm.to_f - 19.0
        snapped_bottom_cm = (desired_bottom_cm / 20.0).round * 20.0
        wall_height_cm.to_f - snapped_bottom_cm
      end

      def expected_block_count(area_m2)
        ((area_m2.to_f.round(4) / 0.08) - 1.0e-9).ceil
      end
    end
  end
end
