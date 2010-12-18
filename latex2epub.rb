#!/usr/bin/ruby
# encoding: utf-8

$KCODE='u'

require 'pathname'
require 'rexml/document'
include REXML

begin
  require 'epubmaker'
rescue LoadError
  $LOAD_PATH.unshift("#{ENV["HOME"]}/review/lib")
  require 'epubmaker'
end

def main
  @params = {
    "toclevel" => 3,
    "secnolevel" => 2,
    "latexml" => "latexml --quiet", # command and options
    "latexmlpost" => "latexmlpost --split", # command and options
    "latex2epubdir" => Pathname.new(__FILE__).realpath.dirname,
    "mathml" => nil,
  }
STDERR.puts @params["latex2epubdir"]

  if ARGV.size != 2
    STDERR.puts <<EOT
latex2epub.rb  TeXfile  YAMLfile
EOT
    exit 1
  end

  yamlfile = ARGV[1]
  @params = @params.merge(EPUBMaker.load_yaml(yamlfile))
  @epub = EPUBMaker.new(2, @params)
  bookname = @params["bookname"]

  if File.exist?("#{bookname}.epub") && (@params["debug"].nil? && @params["basedebug"].nil?)
    STDERR.puts "#{bookname}.epub exists. Please remove or rename it first."
    exit 1
  end

  texfile = ARGV[0]
  xmlfile = File.basename(texfile).sub(/\.tex\Z/i, '.xml')
  xhtmlfile = File.basename(texfile).sub(/\.tex\Z/i, '.xhtml')
  
  basetmp = "out"
  basetmp = Dir.mktmpdir if @params["basedebug"].nil?

  fork {
    exec("#{@params['latexml']} --destination=#{basetmp}/#{xmlfile} #{texfile}")
  }
  Process.waitall

  mathparams = @params["mathml"].nil? ? "--mathimages --stylesheet=#{@params["latex2epubdir"]}/libs/style-#{@params["language"]}/LaTeXML-epub-nomathml.xsl" :
    "--stylesheet=#{@params["latex2epubdir"]}/libs/style-#{@params["language"]}/LaTeXML-epub.xsl"

  # FIXME: needs to replace pool also...
  fork {
    exec("#{@params['latexmlpost']} --format=xhtml #{mathparams} --sourcedirectory=#{File.dirname(texfile)} --destination=#{basetmp}/#{xhtmlfile} #{basetmp}/#{xmlfile}")
  }
  Process.waitall
  File.unlink("#{basetmp}/#{xmlfile}") if @params["basedebug"].nil?

  @epub.data.push(Ec.new({ "href" => xhtmlfile,
                           "title" => @params["title"],
                           "level" => 1,
                         }))
  registered = tocparse("#{basetmp}/#{xhtmlfile}")
  registered.push(xhtmlfile)

  importotherfiles(basetmp, registered, basetmp)

  epubtmpdir = @params["debug"].nil? ? nil : "#{Dir.pwd}/#{bookname}"
  Dir.mkdir(bookname) unless @params["debug"].nil?

  @epub.makeepub("#{bookname}.epub", basetmp, epubtmpdir)
  FileUtils.rm_r(basetmp) if @params["basedebug"].nil?
end

def importotherfiles(dir, registered, base=nil)
  # loop and register
  Dir.foreach(dir) do |f|
    next if f =~ /\A\./ || registered.include?(f)
    if FileTest.directory?("#{dir}/#{f}")
      importotherfiles("#{dir}/#{f}", registered, base) 
    else
      dir.chop! if dir =~ /\/\Z/
      if base.nil?
        @epub.data.push(Ec.new({ "href" => "#{dir}/#{f}"}))
      else
        @epub.data.push(Ec.new({ "href" => "#{dir.sub(base, '')}/#{f}"}))
      end
    end
  end
end

def tocparse(topfile)
  # parse toppage file and get toc
  registered = []
  doc = Document.new(File.new(topfile)).root
  doc.each_element(%Q(//div[@class="main"]/div/div/ul[@class="toc"])) do |e|
    e.each_element("li/a") do |e2|
      @epub.data.push(Ec.new({
                               "href" => e2.attributes["href"],
                               "title" => e2.text.to_s,
                               "level" => 1, # FIXME
                             }))
      registered << e2.attributes["href"]
    end
  end
  return registered
end

main
