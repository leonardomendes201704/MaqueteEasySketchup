module LeonardoLabs
  module PlanForgeBuilder
    class SettingsDialog
      WIDTH = 420
      HEIGHT = 920

      class << self
        def show
          dialog.show
          dialog.bring_to_front if dialog.respond_to?(:bring_to_front)
          push_state
        end

        def push_state(message = nil)
          payload = JSON.generate(Settings.ui_state(message))
          dialog.execute_script("window.PlanForgePanel && window.PlanForgePanel.bootstrap(#{payload});")
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

          panel.set_on_closed do
            @dialog = nil
          end

          panel
        end
      end
    end
  end
end
