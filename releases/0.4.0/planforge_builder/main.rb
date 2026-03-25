require 'sketchup.rb'
require 'json'
require 'fileutils'

module LeonardoLabs
  module PlanForgeBuilder
    PLUGIN_ID = 'leonardo_labs_planforge_builder'.freeze unless const_defined?(:PLUGIN_ID)
    EXTENSION_NAME = 'PlanForge Builder'.freeze unless const_defined?(:EXTENSION_NAME)
    EXTENSION_VERSION = '0.4.0'.freeze unless const_defined?(:EXTENSION_VERSION)
    ROOT = File.dirname(__FILE__).freeze unless const_defined?(:ROOT)
  end
end

require File.join(LeonardoLabs::PlanForgeBuilder::ROOT, 'diagnostics')
require File.join(LeonardoLabs::PlanForgeBuilder::ROOT, 'settings')
require File.join(LeonardoLabs::PlanForgeBuilder::ROOT, 'geometry_builder')
require File.join(LeonardoLabs::PlanForgeBuilder::ROOT, 'wall_tool')
require File.join(LeonardoLabs::PlanForgeBuilder::ROOT, 'door_tool')
require File.join(LeonardoLabs::PlanForgeBuilder::ROOT, 'window_tool')
require File.join(LeonardoLabs::PlanForgeBuilder::ROOT, 'ui')
require File.join(LeonardoLabs::PlanForgeBuilder::ROOT, 'commands')
require File.join(LeonardoLabs::PlanForgeBuilder::ROOT, 'smoke_test')

module LeonardoLabs
  module PlanForgeBuilder
    extend self

    def bootstrap
      return if defined?(@bootstrapped) && @bootstrapped

      CommandRegistry.install
      SmokeTest.run_if_requested
      Diagnostics.write("Bootstrapped #{EXTENSION_NAME} v#{EXTENSION_VERSION} on SketchUp #{Sketchup.version}.")
      @bootstrapped = true
    rescue StandardError => error
      Diagnostics.error('bootstrap', error)
      UI.messagebox("#{EXTENSION_NAME} nao conseguiu iniciar.\n\n#{error.message}")
    end

    def show_panel
      SettingsDialog.show
    rescue StandardError => error
      Diagnostics.error('show_panel', error)
      UI.messagebox("#{EXTENSION_NAME}: erro ao abrir o painel.\n\n#{error.message}")
    end

    def activate_wall_tool
      Sketchup.active_model.select_tool(WallTool.new)
    rescue StandardError => error
      Diagnostics.error('activate_wall_tool', error)
      UI.messagebox("#{EXTENSION_NAME}: erro ao ativar a ferramenta.\n\n#{error.message}")
    end

    def activate_door_tool
      Sketchup.active_model.select_tool(DoorTool.new)
    rescue StandardError => error
      Diagnostics.error('activate_door_tool', error)
      UI.messagebox("#{EXTENSION_NAME}: erro ao ativar a ferramenta de porta.\n\n#{error.message}")
    end

    def activate_window_tool
      Sketchup.active_model.select_tool(WindowTool.new)
    rescue StandardError => error
      Diagnostics.error('activate_window_tool', error)
      UI.messagebox("#{EXTENSION_NAME}: erro ao ativar a ferramenta de janela.\n\n#{error.message}")
    end
  end
end

LeonardoLabs::PlanForgeBuilder.bootstrap
