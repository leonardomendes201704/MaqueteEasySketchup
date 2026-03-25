module LeonardoLabs
  module PlanForgeBuilder
    class PanelSelectionObserver < Sketchup::SelectionObserver
      def onSelectionBulkChange(_selection)
        SettingsDialog.push_state
      end

      def onSelectionCleared(_selection)
        SettingsDialog.push_state
      end
    end

    class SettingsDialog
      WIDTH = 420
      HEIGHT = 920

      class << self
        def show
          install_selection_observer
          dialog.show
          dialog.bring_to_front if dialog.respond_to?(:bring_to_front)
          push_state
        end

        def push_state(message = nil)
          panel = @dialog
          return unless panel

          state = Settings.ui_state(message)
          state[:selection] = ParametricEditor.selection_state if defined?(ParametricEditor)
          payload = JSON.generate(state)
          panel.execute_script("window.PlanForgePanel && window.PlanForgePanel.bootstrap(#{payload});")
        end

        private

        def dialog
          @dialog ||= build_dialog
        end

        def build_dialog
          panel = UI::HtmlDialog.new(
            :dialog_title => "#{EXTENSION_NAME} - Configuracoes",
            :preferences_key => "#{PLUGIN_ID}.settings_panel",
            :scrollable => true,
            :resizable => true,
            :width => WIDTH,
            :height => HEIGHT,
            :style => UI::HtmlDialog::STYLE_DIALOG
          )

          panel.set_file(File.join(ROOT, 'html', 'panel.html'))

          panel.add_action_callback('ready') do |_context|
            push_state
          end

          panel.add_action_callback('saveSettings') do |_context, payload|
            Settings.update(payload || {})
            push_state('Configuracoes atualizadas.')
          end

          panel.add_action_callback('resetSettings') do |_context|
            Settings.reset!
            push_state('Configuracoes padrao restauradas.')
          end

          panel.add_action_callback('activateWallTool') do |_context|
            PlanForgeBuilder.activate_wall_tool
            push_state('Ferramenta ativa. Feche o contorno para criar o piso automaticamente.')
          end

          panel.add_action_callback('activateDoorTool') do |_context|
            PlanForgeBuilder.activate_door_tool
            push_state('Ferramenta de porta ativa. Passe o mouse sobre uma parede e clique para confirmar o corte.')
          end

          panel.add_action_callback('activateWindowTool') do |_context|
            PlanForgeBuilder.activate_window_tool
            push_state('Ferramenta de janela ativa. O topo aproxima da altura das portas quando estiver perto.')
          end

          panel.add_action_callback('generateBaseboards') do |_context|
            success = PlanForgeBuilder.generate_baseboards_for_selection
            push_state(success ? 'Rodape gerado ou regenerado para o comodo selecionado.' : 'Selecione um comodo do plugin para gerar o rodape.')
          end

          panel.add_action_callback('refreshSelectionState') do |_context|
            push_state('Selecao atualizada.')
          end

          panel.add_action_callback('applyWallEdits') do |_context, payload|
            success = PlanForgeBuilder.apply_wall_edits(payload || {})
            push_state('Nao foi possivel atualizar a parede.') unless success
          end

          panel.add_action_callback('applyOpeningEdits') do |_context, payload|
            success = PlanForgeBuilder.apply_opening_edits(payload || {})
            push_state('Nao foi possivel atualizar a abertura.') unless success
          end

          panel.add_action_callback('regenerateSelectedRoom') do |_context|
            success = PlanForgeBuilder.regenerate_selected_room
            push_state('Nao foi possivel regenerar o comodo selecionado.') unless success
          end

          panel.set_on_closed do
            @dialog = nil
          end

          panel
        end

        def install_selection_observer
          model = Sketchup.active_model
          return unless model
          return if defined?(@observed_selection) && @observed_selection == model.selection

          @selection_observer ||= PanelSelectionObserver.new
          model.selection.add_observer(@selection_observer)
          @observed_selection = model.selection
        end
      end
    end
  end
end
