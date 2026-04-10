module LeonardoLabs
  module PlanForgeBuilder
    module MaterialMemorialPdf
      extend self

      PDF_RUNTIME_PATHS = %w[
        pdf-core-0.9.0
        ttfunk-1.8.0
        prawn-2.4.0
        prawn-table-0.2.2
      ].freeze

      PAGE_MARGIN = [42, 42, 54, 42].freeze
      COLORS = {
        :ink => '1F1A17',
        :muted => '6E655D',
        :line => 'D4CABF',
        :sand => 'F3ECE2',
        :sand_dark => 'E7DDD1',
        :accent => 'A86C3F',
        :accent_soft => 'F0DED0',
        :notice => 'F8F2EA'
      }.freeze

      def write(report, output_path)
        ensure_pdf_runtime!

        target = output_path.to_s.strip
        raise ArgumentError, 'Informe um caminho valido para salvar o memorial em PDF.' if target.empty?

        FileUtils.mkdir_p(File.dirname(target))
        Diagnostics.write("material_memorial_pdf.write start: #{target}") if defined?(Diagnostics)
        Prawn::Document.generate(
          target,
          :page_size => 'A4',
          :page_layout => :portrait,
          :margin => PAGE_MARGIN,
          :compress => false,
          :info => pdf_metadata(report)
        ) do |pdf|
          build_document(pdf, report)
        end
        Diagnostics.write("material_memorial_pdf.write done: #{target}") if defined?(Diagnostics)

        target
      end

      private

      def ensure_pdf_runtime!
        return if defined?(@pdf_runtime_loaded) && @pdf_runtime_loaded

        PDF_RUNTIME_PATHS.each do |folder|
          lib_path = File.join(ROOT, 'vendor', 'gems', 'gems', folder, 'lib')
          next unless File.directory?(lib_path)
          next if $LOAD_PATH.include?(lib_path)

          $LOAD_PATH.unshift(lib_path)
        end
        require 'matrix'
        require 'prawn'
        @pdf_runtime_loaded = true
      rescue LoadError => error
        raise LoadError, "Nao foi possivel carregar o motor PDF vendorizado (#{error.message})."
      end

      def pdf_metadata(report)
        {
          :Title => report[:title].to_s,
          :Author => report.dig(:header, :responsible_name).to_s,
          :Subject => 'Memorial descritivo e quantitativo de alvenaria convertida em blocos',
          :Creator => EXTENSION_NAME,
          :Producer => EXTENSION_NAME
        }
      end

      def build_document(pdf, report)
        pdf.font('Helvetica')
        pdf.fill_color(COLORS[:ink])
        pdf.stroke_color(COLORS[:line])

        build_cover(pdf, report)
        build_criteria_page(pdf, report)
        build_groups(pdf, report)
        build_summary_page(pdf, report)
        add_footer(pdf, report)
      end

      def add_footer(pdf, report)
        issued_label = report[:issued_at].strftime('%d/%m/%Y')
        pdf.number_pages(
          "Emitido em #{issued_label}  |  Pagina <page> de <total>",
          :at => [pdf.bounds.left, 10],
          :align => :right,
          :size => 8,
          :color => COLORS[:muted],
          :start_count_at => 1
        )
      end

      def build_cover(pdf, report)
        pdf.fill_color(COLORS[:accent])
        pdf.fill_rectangle([pdf.bounds.left, pdf.cursor], pdf.bounds.width, 10)
        pdf.move_down 20
        pdf.fill_color(COLORS[:ink])
        pdf.text(report[:title].to_s, :size => 22, :style => :bold, :align => :center)
        pdf.move_down 8
        pdf.fill_color(COLORS[:muted])
        pdf.text('Memorial tecnico de materiais e quantitativos de alvenaria', :size => 11, :align => :center)
        pdf.fill_color(COLORS[:ink])
        pdf.move_down 20
        draw_section_title(pdf, 'Identificacao do memorial')
        draw_key_value_box(
          pdf,
          [
            ['Obra', cover_value(report.dig(:header, :project_name))],
            ['Cliente', cover_value(report.dig(:header, :client_name))],
            ['Local', cover_value(report.dig(:header, :site_name))],
            ['Responsavel tecnico', cover_value(report.dig(:header, :responsible_name))],
            ['Registro CREA/CAU', cover_value(report.dig(:header, :responsible_registry))],
            ['Data de emissao', report[:issued_at].strftime('%d/%m/%Y')],
            ['Modelo de origem', report[:model_name].to_s]
          ]
        )

        pdf.move_down 18
        draw_section_title(pdf, 'Escopo do documento')
        draw_paragraph_box(
          pdf,
          'Consolidacao completa, em escopo do modelo atual, de todas as paredes convertidas em blocos pelo PlanForge Builder. O documento resume alvenaria, argamassa de assentamento e elementos estruturais gerados para as paredes convertidas.'
        )

        pdf.move_down 18
        draw_section_title(pdf, 'Resumo executivo')
        draw_simple_rows(
          pdf,
          [
            ['Paredes convertidas', format_integer(report.dig(:summary, :wall_count))],
            ['Blocos totais (un)', format_integer(report.dig(:summary, :block_count))],
            ['Argamassa total (m3)', format_decimal(report.dig(:summary, :mortar_volume_m3), 3)],
            ['Cimento total (kg)', format_decimal(report.dig(:summary, :mortar_cement_kg), 1)],
            ['Cal total (kg)', format_decimal(report.dig(:summary, :mortar_lime_kg), 1)],
            ['Areia total (m3)', format_decimal(report.dig(:summary, :mortar_sand_m3), 3)],
            ['Concreto estrutural total (m3)', format_decimal(report.dig(:summary, :total_concrete_volume_m3), 3)]
          ],
          :label_ratio => 0.42
        )

        notes = report.dig(:header, :notes).to_s.strip
        unless notes.empty?
          pdf.move_down 18
          draw_notice_box(pdf, 'Observacoes gerais', [notes])
        end
      end

      def build_criteria_page(pdf, report)
        pdf.start_new_page
        draw_page_header(pdf, 'Criterios adotados', 'Premissas utilizadas para o levantamento quantitativo da alvenaria convertida em blocos.')
        draw_bullet_box(pdf, Array(report[:criteria]))

        pdf.move_down 18
        draw_section_title(pdf, 'Consolidado principal')
        draw_simple_rows(
          pdf,
          [
            ['Area liquida total (m2)', format_decimal(report.dig(:summary, :net_area_m2), 2)],
            ['Blocos totais (un)', format_integer(report.dig(:summary, :block_count))],
            ['Argamassa total (m3)', format_decimal(report.dig(:summary, :mortar_volume_m3), 3)],
            ['Cimento total (kg)', format_decimal(report.dig(:summary, :mortar_cement_kg), 1)],
            ['Cal total (kg)', format_decimal(report.dig(:summary, :mortar_lime_kg), 1)],
            ['Areia total (m3)', format_decimal(report.dig(:summary, :mortar_sand_m3), 3)],
            ['Concreto estrutural total (m3)', format_decimal(report.dig(:summary, :total_concrete_volume_m3), 3)]
          ],
          :label_ratio => 0.42
        )
      end

      def build_groups(pdf, report)
        Array(report[:groups]).each do |group|
          build_group_summary_page(pdf, group)
          Array(group[:walls]).each do |wall|
            build_wall_page(pdf, group, wall)
          end
        end
      end

      def build_group_summary_page(pdf, group)
        pdf.start_new_page
        draw_page_header(pdf, group[:label].to_s, "Paredes consolidadas neste grupo: #{group[:wall_count]}")

        draw_section_title(pdf, 'Resumo do grupo')
        draw_simple_rows(
          pdf,
          [
            ['Area liquida total (m2)', format_decimal(group.dig(:totals, :net_area_m2), 2)],
            ['Blocos totais (un)', format_integer(group.dig(:totals, :block_count))],
            ['Argamassa total (m3)', format_decimal(group.dig(:totals, :mortar_volume_m3), 3)],
            ['Concreto estrutural (m3)', format_decimal(group.dig(:totals, :total_concrete_volume_m3), 3)],
            ['Colunas (un)', format_integer(group.dig(:totals, :column_count))],
            ['Cinta superior (m)', format_decimal(group.dig(:totals, :bond_beam_length_m), 2)],
            ['Vergas (un)', format_integer(group.dig(:totals, :lintel_count))],
            ['Contra-vergas (un)', format_integer(group.dig(:totals, :sill_beam_count))]
          ],
          :label_ratio => 0.42
        )

        pdf.move_down 18
        draw_section_title(pdf, 'Mapa rapido das paredes')
        draw_simple_rows(
          pdf,
          Array(group[:walls]).map do |wall|
            [
              wall[:label].to_s,
              "Area liquida #{format_decimal(wall[:net_area_m2], 2)} m2  |  Blocos #{format_integer(wall[:block_count])}  |  Argamassa #{format_decimal(wall[:mortar_volume_m3], 3)} m3  |  Concreto #{format_decimal(wall[:total_concrete_volume_m3], 3)} m3"
            ]
          end,
          :label_ratio => 0.24
        )
      end

      def build_wall_page(pdf, group, wall)
        pdf.start_new_page
        draw_page_header(
          pdf,
          "#{group[:label]}  |  #{wall[:label]}",
          "Area liquida #{format_decimal(wall[:net_area_m2], 2)} m2  |  Blocos #{format_integer(wall[:block_count])}"
        )

        draw_section_title(pdf, 'Dados principais')
        draw_simple_rows(
          pdf,
          [
            ['Comprimento (m)', format_decimal(wall[:length_m], 2)],
            ['Altura (m)', format_decimal(wall[:height_m], 2)],
            ['Aberturas (m2)', format_decimal(wall[:opening_area_m2], 2)],
            ['Bloco adotado', value_or_blank(wall[:block_type])]
          ],
          :label_ratio => 0.42
        )

        pdf.move_down 18
        draw_section_title(pdf, 'Quantitativos de alvenaria')
        draw_simple_rows(
          pdf,
          [
            ['Area bruta (m2)', format_decimal(wall[:gross_area_m2], 2)],
            ['Area de aberturas (m2)', format_decimal(wall[:opening_area_m2], 2)],
            ['Area liquida (m2)', format_decimal(wall[:net_area_m2], 2)],
            ['Quantidade de blocos (un)', format_integer(wall[:block_count])],
            ['Traco de argamassa', value_or_blank(wall[:mortar_mix])],
            ['Argamassa (m3)', format_decimal(wall[:mortar_volume_m3], 3)],
            ['Cimento (kg)', format_decimal(wall[:mortar_cement_kg], 1)],
            ['Cal (kg)', format_decimal(wall[:mortar_lime_kg], 1)],
            ['Areia (m3)', format_decimal(wall[:mortar_sand_m3], 3)]
          ]
        )

        pdf.move_down 16
        draw_section_title(pdf, 'Elementos estruturais')
        draw_simple_rows(
          pdf,
          [
            ['Colunas (un)', format_integer(wall[:column_count])],
            ['Cinta superior (m)', format_decimal(wall[:bond_beam_length_m], 2)],
            ['Vergas (un)', format_integer(wall[:lintel_count])],
            ['Vergas totais (m)', format_decimal(wall[:lintel_length_m], 2)],
            ['Contra-vergas (un)', format_integer(wall[:sill_beam_count])],
            ['Contra-vergas totais (m)', format_decimal(wall[:sill_beam_length_m], 2)],
            ['Volume estrutural total (m3)', format_decimal(wall[:total_concrete_volume_m3], 3)]
          ]
        )

        warnings = split_warnings(wall[:warning_text])
        pdf.move_down 16
        if warnings.empty?
          draw_notice_box(pdf, 'Avisos da parede', ['Sem observacoes adicionais para esta parede.'], :muted)
        else
          draw_notice_box(pdf, 'Avisos da parede', warnings)
        end
      end

      def build_summary_page(pdf, report)
        pdf.start_new_page
        draw_page_header(pdf, 'Resumo geral do modelo', 'Consolidacao final das paredes convertidas em blocos no arquivo atual.')

        draw_section_title(pdf, 'Indicadores consolidados')
        draw_simple_rows(
          pdf,
          [
            ['Grupos consolidados', format_integer(report.dig(:summary, :group_count))],
            ['Paredes consolidadas', format_integer(report.dig(:summary, :wall_count))],
            ['Area liquida total (m2)', format_decimal(report.dig(:summary, :net_area_m2), 2)],
            ['Blocos totais (un)', format_integer(report.dig(:summary, :block_count))],
            ['Argamassa total (m3)', format_decimal(report.dig(:summary, :mortar_volume_m3), 3)],
            ['Cimento total (kg)', format_decimal(report.dig(:summary, :mortar_cement_kg), 1)],
            ['Cal total (kg)', format_decimal(report.dig(:summary, :mortar_lime_kg), 1)],
            ['Areia total (m3)', format_decimal(report.dig(:summary, :mortar_sand_m3), 3)],
            ['Colunas estruturais (un)', format_integer(report.dig(:summary, :column_count))],
            ['Cinta superior (m)', format_decimal(report.dig(:summary, :bond_beam_length_m), 2)],
            ['Vergas (un)', format_integer(report.dig(:summary, :lintel_count))],
            ['Contra-vergas (un)', format_integer(report.dig(:summary, :sill_beam_count))],
            ['Concreto estrutural (m3)', format_decimal(report.dig(:summary, :total_concrete_volume_m3), 3)]
          ],
          :label_ratio => 0.42
        )

        notes = report.dig(:header, :notes).to_s.strip
        unless notes.empty?
          pdf.move_down 18
          draw_notice_box(pdf, 'Observacoes finais', [notes])
        end
      end

      def draw_page_header(pdf, title, subtitle = nil)
        pdf.fill_color(COLORS[:accent_soft])
        pdf.fill_rectangle([pdf.bounds.left, pdf.cursor], pdf.bounds.width, 30)
        pdf.fill_color(COLORS[:ink])
        pdf.bounding_box([pdf.bounds.left + 12, pdf.cursor - 6], :width => pdf.bounds.width - 24, :height => 20) do
          pdf.text(title.to_s, :size => 16, :style => :bold)
        end
        pdf.move_down 42
        return if subtitle.to_s.strip.empty?

        pdf.fill_color(COLORS[:muted])
        pdf.text(subtitle.to_s, :size => 10)
        pdf.fill_color(COLORS[:ink])
        pdf.move_down 6
      end

      def draw_section_title(pdf, text)
        pdf.fill_color(COLORS[:ink])
        pdf.text(text.to_s, :size => 13, :style => :bold)
        pdf.move_down 6
        pdf.stroke_color(COLORS[:line])
        pdf.stroke_horizontal_rule
        pdf.move_down 10
      end

      def draw_paragraph_box(pdf, text)
        height = pdf.height_of(text.to_s, :width => pdf.bounds.width - 24, :size => 10, :leading => 2) + 20
        ensure_space(pdf, height + 8)
        pdf.fill_color(COLORS[:sand])
        pdf.fill_rectangle([pdf.bounds.left, pdf.cursor], pdf.bounds.width, height)
        pdf.fill_color(COLORS[:ink])
        pdf.text_box(text.to_s, :at => [pdf.bounds.left + 12, pdf.cursor - 8], :width => pdf.bounds.width - 24, :height => height - 12, :size => 10, :leading => 2)
        pdf.move_down(height + 4)
      end

      def draw_bullet_box(pdf, items)
        lines = Array(items).map { |item| "- #{item}" }
        text = lines.join("\n")
        height = pdf.height_of(text, :width => pdf.bounds.width - 24, :size => 10, :leading => 3) + 20
        ensure_space(pdf, height + 8)
        pdf.fill_color(COLORS[:sand])
        pdf.fill_rectangle([pdf.bounds.left, pdf.cursor], pdf.bounds.width, height)
        pdf.fill_color(COLORS[:ink])
        pdf.text_box(text, :at => [pdf.bounds.left + 12, pdf.cursor - 8], :width => pdf.bounds.width - 24, :height => height - 12, :size => 10, :leading => 3)
        pdf.move_down(height + 4)
      end

      def draw_key_value_box(pdf, rows)
        draw_simple_rows(pdf, rows, :label_ratio => 0.34)
      end

      def draw_simple_rows(pdf, rows, options = {})
        label_ratio = options[:label_ratio] || 0.34
        total_width = pdf.bounds.width
        label_width = total_width * label_ratio
        value_width = total_width - label_width
        x = pdf.bounds.left
        y = pdf.cursor

        Array(rows).each do |row|
          label = row[0].to_s
          value = row[1].to_s
          height = row_height(pdf, label, value, label_width, value_width)
          ensure_space(pdf, height + 4)
          y = pdf.cursor

          pdf.fill_color(COLORS[:sand])
          pdf.fill_rectangle([x, y], label_width, height)
          pdf.fill_color(COLORS[:ink])
          pdf.stroke_color(COLORS[:line])
          pdf.stroke_horizontal_line(x, x + total_width, :at => y - height)

          pdf.text_box(label, :at => [x + 8, y - 6], :width => label_width - 14, :height => height - 8, :size => 9, :style => :bold)
          pdf.text_box(value, :at => [x + label_width + 8, y - 6], :width => value_width - 14, :height => height - 8, :size => 9, :leading => 1)
          pdf.move_down(height)
        end

        pdf.move_down 4
      end

      def draw_notice_box(pdf, title, items, tone = :accent)
        lines = Array(items).map { |item| "- #{item}" }
        body = lines.join("\n")
        text_height = pdf.height_of(body, :width => pdf.bounds.width - 24, :size => 9, :leading => 2)
        box_height = text_height + 34
        ensure_space(pdf, box_height + 6)

        fill = tone == :muted ? COLORS[:sand] : COLORS[:notice]
        pdf.fill_color(fill)
        pdf.fill_rectangle([pdf.bounds.left, pdf.cursor], pdf.bounds.width, box_height)
        pdf.stroke_color(COLORS[:line])
        pdf.stroke_rectangle([pdf.bounds.left, pdf.cursor], pdf.bounds.width, box_height)
        pdf.fill_color(COLORS[:ink])
        pdf.text_box(title.to_s, :at => [pdf.bounds.left + 10, pdf.cursor - 8], :width => pdf.bounds.width - 20, :height => 16, :size => 11, :style => :bold)
        pdf.text_box(body, :at => [pdf.bounds.left + 10, pdf.cursor - 26], :width => pdf.bounds.width - 20, :height => text_height + 4, :size => 9, :leading => 2)
        pdf.move_down(box_height + 4)
      end

      def ensure_space(pdf, needed_height)
        return if pdf.cursor >= needed_height

        pdf.start_new_page
      end

      def split_warnings(text)
        text.to_s.split('|').map(&:strip).reject(&:empty?)
      end

      def row_height(pdf, label, value, label_width, value_width)
        label_height = pdf.height_of(label.to_s, :width => label_width - 14, :size => 9)
        value_height = pdf.height_of(value.to_s, :width => value_width - 14, :size => 9, :leading => 1)
        [[label_height, value_height].max + 12, 22].max
      end

      def cover_value(value)
        text = value.to_s.strip
        text.empty? ? 'Nao informado' : text
      end

      def format_decimal(value, precision)
        format("%.#{precision}f", value.to_f).tr('.', ',')
      end

      def format_integer(value)
        value.to_i.to_s
      end

      def value_or_blank(value)
        text = value.to_s.strip
        text.empty? ? ' ' : text
      end
    end
  end
end
