require 'sketchup.rb'
require 'json'
require 'fileutils'

module LeonardoLabs
  module PlanForgeBuilder
    PLUGIN_ID = 'leonardo_labs_planforge_builder'.freeze unless const_defined?(:PLUGIN_ID)
    EXTENSION_NAME = 'PlanForge Builder'.freeze unless const_defined?(:EXTENSION_NAME)
    EXTENSION_VERSION = '0.8.0'.freeze unless const_defined?(:EXTENSION_VERSION)
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
LeonardoLabs::PlanForgeBuilder.safe_require('layer_manager')
LeonardoLabs::PlanForgeBuilder.safe_require('material_manager')
LeonardoLabs::PlanForgeBuilder.safe_require('geometry_builder')
LeonardoLabs::PlanForgeBuilder.safe_require('baseboard_builder')
LeonardoLabs::PlanForgeBuilder.safe_require('room_builder')
LeonardoLabs::PlanForgeBuilder.safe_require('room_regenerator')
LeonardoLabs::PlanForgeBuilder.safe_require('parametric_editor')
LeonardoLabs::PlanForgeBuilder.safe_require('room_tool')
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

    def prompt_room_tool
      values = UI.inputbox(
        ['Largura interna do comodo', 'Profundidade interna do comodo'],
        [Settings.current[:room_width_cm].to_f.cm, Settings.current[:room_depth_cm].to_f.cm],
        'Gerar comodo'
      )
      return false unless values

      width = coerce_length(values[0])
      depth = coerce_length(values[1])
      raise ArgumentError, 'As medidas do comodo devem ser maiores que zero.' if width <= 1.mm || depth <= 1.mm

      Settings.update(
        :room_width_cm => (width / 1.cm).round(2),
        :room_depth_cm => (depth / 1.cm).round(2)
      )
      Sketchup.active_model.select_tool(RoomTool.new(width, depth, Settings.to_h))
      true
    rescue StandardError => error
      Diagnostics.error('prompt_room_tool', error)
      UI.messagebox("#{EXTENSION_NAME}: erro ao preparar a geracao do comodo.\n\n#{error.message}")
      false
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

    def apply_wall_edits(payload)
      message = ParametricEditor.apply_wall_edits(Sketchup.active_model, Sketchup.active_model.selection, payload || {})
      SettingsDialog.push_state(message)
      true
    rescue StandardError => error
      Diagnostics.error('apply_wall_edits', error)
      UI.messagebox("#{EXTENSION_NAME}: erro ao editar a parede.\n\n#{error.message}")
      false
    end

    def apply_opening_edits(payload)
      message = ParametricEditor.apply_opening_edits(Sketchup.active_model, Sketchup.active_model.selection, payload || {})
      SettingsDialog.push_state(message)
      true
    rescue StandardError => error
      Diagnostics.error('apply_opening_edits', error)
      UI.messagebox("#{EXTENSION_NAME}: erro ao editar a abertura.\n\n#{error.message}")
      false
    end

    def regenerate_selected_room
      message = ParametricEditor.regenerate_selected_room(Sketchup.active_model, Sketchup.active_model.selection)
      SettingsDialog.push_state(message)
      true
    rescue StandardError => error
      Diagnostics.error('regenerate_selected_room', error)
      UI.messagebox("#{EXTENSION_NAME}: erro ao regenerar o comodo.\n\n#{error.message}")
      false
    end

    private

    def coerce_length(value)
      return value.to_f if value.is_a?(Numeric)

      value.to_l.to_f
    end
  end
end

LeonardoLabs::PlanForgeBuilder.bootstrap
