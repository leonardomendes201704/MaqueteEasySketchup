require 'sketchup.rb'
require 'json'
require 'fileutils'

module LeonardoLabs
  module PlanForgeBuilder
    PLUGIN_ID = 'leonardo_labs_planforge_builder'.freeze unless const_defined?(:PLUGIN_ID)
    EXTENSION_NAME = 'PlanForge Builder'.freeze unless const_defined?(:EXTENSION_NAME)
    EXTENSION_VERSION = '0.5.0'.freeze unless const_defined?(:EXTENSION_VERSION)
    ROOT = File.dirname(__FILE__).freeze unless const_defined?(:ROOT)

    def self.bootstrap_log_path
      base = ENV['LOCALAPPDATA'] || ENV['TEMP'] || ROOT
      folder = File.join(base, 'PlanForgeBuilder')
      FileUtils.mkdir_p(folder)
      File.join(folder, 'planforge_builder_bootstrap.log')
    rescue StandardError
      File.join(ENV['TEMP'] || ROOT, 'planforge_builder_bootstrap.log')
    end

    def self.safe_require(relative_path)
      require File.join(ROOT, relative_path)
    rescue Exception => error
      File.open(bootstrap_log_path, 'a') do |file|
        file.puts("[#{Time.now.strftime('%Y-%m-%d %H:%M:%S')}] require '#{relative_path}' failed: #{error.class}: #{error.message}")
        file.puts(Array(error.backtrace).first(10).join("\n"))
      end
      raise
    end
  end
end

LeonardoLabs::PlanForgeBuilder.safe_require('diagnostics')
LeonardoLabs::PlanForgeBuilder.safe_require('settings')
LeonardoLabs::PlanForgeBuilder.safe_require('geometry_builder')
LeonardoLabs::PlanForgeBuilder.safe_require('baseboard_builder')
LeonardoLabs::PlanForgeBuilder.safe_require('wall_tool')
LeonardoLabs::PlanForgeBuilder.safe_require('door_tool')
LeonardoLabs::PlanForgeBuilder.safe_require('window_tool')
LeonardoLabs::PlanForgeBuilder.safe_require('ui')
LeonardoLabs::PlanForgeBuilder.safe_require('commands')
LeonardoLabs::PlanForgeBuilder.safe_require('smoke_test')

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

    def generate_baseboards_for_selection
      model = Sketchup.active_model
      model.start_operation('PlanForge Builder - Gerar rodape', true)
      groups = BaseboardBuilder.build_from_selection(model, model.selection, Settings.to_h)
      if groups.empty?
        model.abort_operation
        UI.messagebox("#{EXTENSION_NAME}: selecione pelo menos uma parede, piso ou rodape de um comodo criado pelo plugin para regenerar o rodape.")
        false
      else
        model.commit_operation
        true
      end
    rescue StandardError => error
      model.abort_operation rescue nil
      Diagnostics.error('generate_baseboards_for_selection', error)
      UI.messagebox("#{EXTENSION_NAME}: erro ao gerar rodape.\n\n#{error.message}")
      false
    end
  end
end

LeonardoLabs::PlanForgeBuilder.bootstrap
