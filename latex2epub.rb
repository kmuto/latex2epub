#!/usr/bin/ruby
# encoding: utf-8
#
# Copyright (c) 2010 Kenshi Muto
#
# This program is free software.
# You can distribute or modify this program under the terms of
# the GNU LGPL, Lesser General Public License version 2.1.
# For details of the GNU LGPL, see the file "COPYING".

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

include EPUBMaker

def main
  @params = {
    "toclevel" => 3,
    "secnolevel" => 2,
    "latexml" => "latexml --quiet", # command and options
    "latexmlpost" => "latexmlpost --split", # command and options
    "latex2epubdir" => Pathname.new(__FILE__).realpath.dirname,
    "epubversion" => 2,
    "mathml" => nil,
    "latexcmd" => "latex",
    "dvipscmd" => "dvips -q -S1 -i -E -j0",
  }

  # FIXME: more options
  if ARGV.size != 2
    STDERR.puts <<EOT
latex2epub.rb  TeXfile  YAMLfile
EOT
    exit 1
  end

  yamlfile = ARGV[1]
  @params = @params.merge(Producer.load(yamlfile))
  @epub = Producer.new(@params)
  bookname = @params["bookname"]

  texfile = ARGV[0]
  xmlfile = File.basename(texfile).sub(/\.tex\Z/i, '.xml')
  xhtmlfile = File.basename(texfile).sub(/\.tex\Z/i, '.xhtml')
  
  basetmp = "#{bookname}-output"
  basetmp = Dir.mktmpdir if @params["basedebug"].nil?

  # Override
  ENV["PERL5LIB"] = "#{@params["latex2epubdir"]}/libs/perl"
  ENV["LATEXMLLATEXCMD"] = @params["latexcmd"]
  ENV["LATEXMLDVIPSCMD"] = @params["dvipscmd"]

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

  @epub.contents.push(Content.new({ "file" => xhtmlfile,
                                    "title" => @params["title"],
                                    "level" => 1,
                                  }))

  @registered = [xhtmlfile]
  tocparse(basetmp, xhtmlfile)

  importotherfiles(basetmp, basetmp)

  epubtmpdir = @params["debug"].nil? ? nil : "#{Dir.pwd}/#{bookname}"
  Dir.mkdir(bookname) unless @params["debug"].nil?

  @epub.produce("#{bookname}.epub", basetmp, epubtmpdir)
  FileUtils.rm_r(basetmp) if @params["basedebug"].nil?
end

def importotherfiles(dir, base=nil)
  # loop and register
  Dir.foreach(dir) do |f|
    next if f =~ /\A\./ || @registered.include?(f)
    next if f =~ /\.cache\Z/ || f =~ /\.xml\Z/
    if FileTest.directory?("#{dir}/#{f}")
      importotherfiles("#{dir}/#{f}", base) 
    else
      dir.chop! if dir =~ /\/\Z/
      if base.nil?
        @epub.contents.push(Content.new({ "file" => "#{dir}/#{f}"}))
      else
        if dir == base
          @epub.contents.push(Content.new({ "file" => "#{f}"}))
        else
          @epub.contents.push(Content.new({ "file" => "#{dir.sub(base + "/", '')}/#{f}"}))
        end
      end
    end
  end
end

def tocparse(base, file)
  # parse toppage file and get toc
  doc = Document.new(File.new("#{base}/#{file}")).root
  doc.each_element(%Q(//head/link[@rel="next"])) do |e|
    level = e.attributes["href"].split(".").size - 1
    @epub.contents.push(Content.new({
                                      "file" => e.attributes["href"],
                                      "title" => e.attributes["title"],
                                      "level" => level,
                                    }))
    @registered << e.attributes["href"]
    tocparse(base, e.attributes["href"])
  end
end

main
