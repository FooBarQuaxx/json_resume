
require 'i18n'
require 'thor'
require 'mustache'
require 'zlib'
require 'pdfkit'
require 'rest-client'
require_relative '../json_resume'

WL_URL = "https://www.writelatex.com/docs"

class String
  def red; "\033[31m#{self}\033[0m" end
  def green; "\033[32m#{self}\033[0m" end
end

class JsonResumeCLI < Thor

  desc "convert /path/to/json/file", "converts the json to pretty resume format"
  option :out, :default=>"html", :banner=>"output_type", :desc=>"html|html_pdf|tex|tex_pdf|md"
  option :template, :banner=>"template_path", :desc=>"path to customized template (optional)"
  option :locale, :default=>"en", :banner=>"locale", :desc=>"en|es|pt"
  option :theme, :default=>"default", :banner=>"theme", :desc=>"default|classic"
  def convert(json_input)
    set_i18n(options[:locale])
    puts "Generating the #{options[:out]} type..."
    begin
      # puts send('convert_to_'+options[:out], json_input, get_template(options))
      puts send('convert_to_'+options[:out], json_input, template)
    rescue Encoding::InvalidByteSequenceError
      puts "ERROR: You need to 'export LC_CTYPE=en_US.UTF-8' ...".green
    end
  end

  desc "sample", "Generates a sample json file in cwd"
  def sample()
    cwd = Dir.pwd
    json_file_paths = Dir["#{@@root}/examples/*.json"]
    json_file_names = json_file_paths.map{|x| File.basename(x)}
    FileUtils.cp json_file_paths, cwd
    msg = "Generated #{json_file_names.join(" ")} in #{cwd}/".green
    msg += "\nYou can now modify it and call: json_resume convert <file.json>"
    puts msg
  end

  no_commands do
    @@root = File.expand_path('../..', File.dirname(__FILE__))

    def template
      return options[:template] if options[:template]
      out_type = options[:out].split('_').first #html for both html, html_pdf
      out_type = 'html' if out_type == 'pdf'
      theme = options[:theme]
      template_path = "#{@@root}/templates/#{theme}_#{out_type}.mustache"
      if !(File.exists? template_path) and theme != 'default'
        puts "Theme #{theme} doesn't exist for #{options[:out]} type yet! Using default...".red
        template_path = "#{@@root}/templates/default_#{out_type}.mustache"
      end
      template_path
    end

    def convert_to_html(json_input, template, dest=Dir.pwd, dir_name='resume')
      dest_dir = "#{dest}/#{dir_name}"
      FileUtils.mkdir_p dest_dir
      FileUtils.cp_r(Dir["#{@@root}/extras/resume_html/*"], dest_dir)
      msg = generate_file(json_input, template, "html", "#{dest_dir}/page.html")
      msg += "\nPlace #{dest_dir}/ in /var/www/ to host."
    end

    def convert_to_pdf(json_input, template, dest=Dir.pwd)
      puts "Defaulting to 'html_pdf'..."
      convert_to_html_pdf(json_input, template, dest)
    end

    def convert_to_html_pdf(json_input, template, dest=Dir.pwd)
      tmp_dir = ".tmp_resume"
      convert_to_html(json_input, template, dest, tmp_dir)
      PDFKit.configure do |config|
        wkhtmltopdf_path = `which wkhtmltopdf`.to_s.strip
        config.wkhtmltopdf = wkhtmltopdf_path unless wkhtmltopdf_path.empty?
        config.default_options = {
          :footer_right => "Page [page] of [toPage]    .\n",
          :footer_font_size => 10,
          :footer_font_name => "Georgia"
        }
      end
      html_file = File.new("#{dest}/#{tmp_dir}/core-page.html")
      # Purge the mobile css properties so that wkhtmlpdf not uses them.
      File.open("#{dest}/#{tmp_dir}/public/css/mobile.css", 'w') {}

      pdf_options = {
        :margin_top => 2.0,
        :margin_left=> 0.0,
        :margin_right => 0.0,
        :margin_bottom => 4.0,
        :page_size => 'Letter'
      }
      kit = PDFKit.new(html_file, pdf_options)

      begin
        kit.to_file(dest+"/resume.pdf")
      rescue Errno::ENOENT => e
        puts "\nTry: sudo apt-get update; sudo apt-get install libxtst6 libfontconfig1".green
        raise e
      end
      FileUtils.rm_rf "#{dest}/#{tmp_dir}"
      msg = "\nGenerated resume.pdf at #{dest}.".green
    end

    def convert_to_tex(json_input, template, dest=Dir.pwd, filename="resume.tex")
      generate_file(json_input, template, "latex", "#{dest}/#{filename}")
    end

    def convert_to_tex_pdf(json_input, template, dest=Dir.pwd)
      file1 = "resume"; filename = "#{file1}.tex"
      convert_to_tex(json_input, template, dest, filename)
      if `which pdflatex` == ""
        puts "It looks like pdflatex is not installed...".red
        puts "Either install it with instructions at..."
        puts "http://dods.ipsl.jussieu.fr/fast/pdflatex_install.html"
        return use_write_latex(dest, filename)
      end
      if `kpsewhich moderncv.cls` == ""
        puts "It looks liks moderncv package for tex is not installed".red
        puts "Read about it here: http://ctan.org/pkg/moderncv"
        return use_write_latex(dest, filename)
      end
      system("pdflatex -shell-escape -interaction=nonstopmode #{dest}/#{filename}")
      [".tex",".out",".aux",".log"].each do |ext|
        FileUtils.rm "#{dest}/#{file1}#{ext}"
      end
      msg = "\nPDF is ready at #{dest}/#{file1}.pdf"
    end

    def use_write_latex(dest, filename)
       reply = ask "Create PDF online using writeLatex ([y]n)?"
       if reply == "" || reply == "y"
          return convert_using_writeLatex(dest, filename)
       end
       msg = "Latex file created at #{dest}/#{filename}".green
    end

    def convert_using_writeLatex(dest, filename)
      tex_file = File.read("#{dest}/#{filename}")
      RestClient.post(WL_URL, :snip => tex_file, :splash => "none") do |response, req, res, &bb|
        FileUtils.rm "#{dest}/#{filename}"
        msg = "\nPDF is ready at #{response.headers[:location]}".green
      end
    end

    def convert_to_md(json_input, template, dest=Dir.pwd)
      generate_file(json_input, template, "markdown", "#{dest}/resume.md")
    end

    def set_i18n(locale)
      I18n.load_path = Dir["#{@@root}/locale/*.yml"]
      I18n.enforce_available_locales = true
      I18n.locale = options[:locale].to_sym
    end

    def i18n(text)
      text.gsub(/##(\w*?)##/) { I18n.t! Regexp.last_match[1], :scope => 'headings' }
    end

    def render(template, hash)
      Mustache.render(i18n(File.read(template)), hash)
    end

    def read(json_input, output_type)
      JsonResume.new(json_input, output_type: output_type)
    end

    def generate_file(json_input, template, output_type, dest)
      resume_obj = read(json_input, output_type)
      obj = render(template, resume_obj.to_hash)
      File.open(dest,'w') {|f| f.write(obj) }
      return "\nGenerated files present at #{dest}".green
    end

  end

end
