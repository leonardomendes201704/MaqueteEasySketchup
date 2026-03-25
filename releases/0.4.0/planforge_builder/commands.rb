module LeonardoLabs
  module PlanForgeBuilder
    module CommandRegistry
      extend self

      def install
        return if defined?(@installed) && @installed

        menu = UI.menu('Extensions').add_submenu(EXTENSION_NAME)
        menu.add_item(panel_command)
        menu.add_item(wall_command)
        menu.add_item(door_command)
        menu.add_item(window_command)

        @toolbar = UI::Toolbar.new(EXTENSION_NAME)
        @toolbar.add_item(panel_command)
        @toolbar.add_item(wall_command)
        @toolbar.add_item(door_command)
        @toolbar.add_item(window_command)
        @toolbar.restore if @toolbar.respond_to?(:restore)

        @installed = true
      end

      def panel_command
        @panel_command ||= begin
          command = UI::Command.new('Abrir painel') { PlanForgeBuilder.show_panel }
          assign_icons(command, 'panel')
          command.menu_text = 'Abrir painel'
          command.tooltip = 'Abrir painel do PlanForge Builder'
          command.status_bar_text = 'Abre o painel com configuracoes, dicas e atalhos da extensao.'
          command
        end
      end

      def wall_command
        @wall_command ||= begin
          command = UI::Command.new('Desenhar paredes') { PlanForgeBuilder.activate_wall_tool }
          assign_icons(command, 'wall')
          command.menu_text = 'Ferramenta de paredes'
          command.tooltip = 'Ativar ferramenta de paredes'
          command.status_bar_text = 'Ativa a ferramenta de desenho rapido de paredes.'
          command
        end
      end

      def door_command
        @door_command ||= begin
          command = UI::Command.new('Corte de porta') { PlanForgeBuilder.activate_door_tool }
          assign_icons(command, 'door')
          command.menu_text = 'Ferramenta de porta'
          command.tooltip = 'Ativar corte de porta'
          command.status_bar_text = 'Ativa a ferramenta de corte de porta sobre paredes do PlanForge Builder.'
          command
        end
      end

      def window_command
        @window_command ||= begin
          command = UI::Command.new('Corte de janela') { PlanForgeBuilder.activate_window_tool }
          assign_icons(command, 'window')
          command.menu_text = 'Ferramenta de janela'
          command.tooltip = 'Ativar corte de janela'
          command.status_bar_text = 'Ativa a ferramenta de corte de janela sobre paredes do PlanForge Builder.'
          command
        end
      end

      private

      def assign_icons(command, icon_name)
        small_icon = File.join(ROOT, 'icons', "#{icon_name}_16.png")
        large_icon = File.join(ROOT, 'icons', "#{icon_name}_24.png")

        command.small_icon = small_icon if File.exist?(small_icon)
        command.large_icon = large_icon if File.exist?(large_icon)
      end
    end
  end
end
