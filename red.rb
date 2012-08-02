#!/usr/bin/env ruby
VER = "0.3 (c) 2009 Dave Nolan textgoeshere.org.uk, github.com/textgoeshere/redcmd"
BANNER =<<-EOS
Red creates Redmine (http://www.redmine.org/) issues from the command line.

==Example==
Add an issue:

    red add -s "New feature" -d "Some longer description text" -t feature -p cashprinter -r high -a "Dave" -f /path/to/attachment
    # =>
    "Created Feature #999 New feature"
       
List some issues (you can reference a Redmine custom query here):
    
    red list 3
    # =>
    Fix widget
    Design thingy
    Document Windows 95 compatibility issues

Command line arguments override settings in the configuration file, which override Redmine form defaults.

==An example configuration file==
username: dave
password: d4ve
url: http://www.myredmineinstance.com
project: redcmd
tracker: bug
priorty: normal   

I recommend creating a configuration file per-project, and sticking it in your path.

# TODO: due, start, done, est. hours
# TODO: custom fields
# TODO: subcommands (list, update, etc.)

#{VER}

==Options==

EOS


begin
  require 'trollop'
  require 'mechanize'
  require 'yaml'
  require 'colorize'
rescue LoadError
  require 'rubygems'
  require 'trollop'
  require 'mechanize'
  require 'yaml'
  require 'colorize'
end

module Textgoeshere
  class RedmineError < StandardError; end
  
  class Red
    SELECTS = %w{priority tracker category assigned_to status}
    
    def initialize(command, opts)
      @opts = opts
      @mech  = Mechanize.new
      login
      send(command)
    end
    
    private
    
    def login
      @mech.get login_url
      @mech.page.form_with(:action => login_action) do |f|
        f.field_with(:name => 'username').value = @opts[:username]
        f.field_with(:name => 'password').value = @opts[:password]
        f.click_button
      end
      catch_redmine_errors
    end
    
    def add
      @mech.get new_issue_url
      @mech.page.form_with(:action => create_issue_action) do |f|
        SELECTS.each do |name|
          value = @opts[name.to_sym]
          unless value.nil?
            field = f.field_with(:name => "issue[#{name}_id]")
            field.value = field.options.detect { |o| o.text.downcase =~ Regexp.new(value) }
            raise RedmineError.new("Cannot find #{name} #{value}") if field.value.nil? || field.value.empty?
          end
        end
        f.field_with(:name => 'issue[subject]').value = @opts[:subject]
        f.field_with(:name => 'issue[description]').value = @opts[:description] || @opts[:subject]
        @opts[:file].each_with_index do |file, i|
          f.file_uploads_with(:name => "attachments[#{i.to_s()}][file]").first.file_name = file
        end
        f.click_button
        catch_redmine_errors
        puts "Created #{@mech.page.search('h2').text}: #{@opts[:subject]}"
      end
    end
    
    def list
      @mech.get(list_issues_url)
      issues = @mech.page.parser.xpath('//table[@class="list issues"]/tbody//tr')
      if issues.empty?
        puts "No issues found at #{list_issues_url}"
      else
        @opts[:number].times do |i|
          issue = issues[i]
          break unless issue
          subject = issue.xpath('td[@class="subject"]/a').inner_html
          id      = issue.xpath('td[@class="subject"]/a').map{|n| n['href']}.first.to_s.split('/')[2]
          status = issue.xpath('td[@class="status"]').inner_text
          tracker = issue.xpath('td[@class="tracker"]').inner_text  #Feature|Bug
          project = issue.xpath('td[@class="project"]').inner_html 
          priority = issue.xpath('td[@class="priority"]').inner_text 
          fixedversion = issue.xpath('td[@class="fixed_version"]').inner_text 
          status = case status
                   when /Accepted/; 'accepted'.yellow
                   when /Unreviewed/; 'unreviewed'.yellow
                   when /Review/; 'on review'.green
                   when /Needs/; 'need info'.yellow
                   when /Insufficient/; 'insufficient'.red
                   when /Merged/; 'merged'.blue
                   when /Duplicate/; 'duplicate'.blue
                   when /Rejected/; 'rejected'.blue
                   when /Re-opened/; 'reopened'.red
                   when /Closed/; 'closed'.blue
                   else status
                   end
          assignedto = issue.xpath('td[@class="assigned_to"]/a').inner_html
          a = assignedto.split(' ')[0]
          if a.nil?
            a = '-' 
          else
            a.downcase!
          end
          if a == @opts[:username].downcase
            a = a.light_blue 
          else
            a = a.white 
          end
          puts "%20s | %6s | %26s | %s" % [a, id, status, subject] unless subject.nil? || subject.empty?
        end
      end
    end
    
    def login_action; '/login'; end
    def login_url; "#{@opts[:url]}#{login_action}"; end
      
    def create_issue_action; "/projects/#{@opts[:project]}/issues/new"; end
    def new_issue_url; "#{@opts[:url]}#{create_issue_action}"; end
    def list_issues_url
#?set_filter=1&f%5B%5D=status_id&op%5Bstatus_id%5D=*&f%5B%5D=assigned_to_id&op%5Bassigned_to_id%5D=%3D&v%5Bassigned_to_id%5D%5B%5D=me&f%5B%5D=&c%5B%5D=project&c%5B%5D=tracker&c%5B%5D=status&c%5B%5D=priority&c%5B%5D=subject&c%5B%5D=assigned_to&c%5B%5D=fixed_version&c%5B%5D=category&c%5B%5D=support_urls&c%5B%5D=cf_13&c%5B%5D=cf_12&c%5B%5D=cf_11
      q = @opts[:q]
      q = @opts[q.to_sym] if q.is_a? String
      params = q ? "?query_id=#{q}" : "" 
      "#{@opts[:url]}/projects/#{@opts[:project]}/issues#{params}"
    end
      
    def catch_redmine_errors
      error_flash = @mech.page.search('.flash.error')[0]
      raise RedmineError.new(error_flash.text) if error_flash
    end
  end
end

# NOTE: Trollop's default default for boolean values is false, not nil, so if extending to include boolean options ensure you explicity set :default => nil

COMMANDS = %w(add list)

global_options = Trollop::options do
  banner BANNER
  opt :username,    "Username",                     :type => String, :short => 'u'
  opt :password,    "Password",                     :type => String, :short => 'p'
  opt :url,         "Url to redmine",               :type => String
  opt :project,     "Project identifier",           :type => String
  opt :filename,    "Configuration file, YAML format, specifying default options.", 
          :type => String, :default => "#{ENV['HOME']}/.red"
  version VER
  stop_on COMMANDS
end

command = ARGV.shift
command_options = case command 
  when "add"
    Trollop::options do
      opt :subject, "Issue subject (title). This must be wrapped in inverted commas like this: \"My new feature\".", 
              :type => String, :required => true
      opt :description, "Description",                  :type => String
      opt :tracker,     "Tracker (bug, feature etc.)",  :type => String
      opt :assigned_to, "Assigned to",                  :type => String
      opt :priority,    "Priority",                     :type => String
      opt :status,      "Status",                       :type => String, :short => 'x'
      opt :category,    "Category",                     :type => String
      opt :file, 		    "File",                         :type => String, :multi => true
    end
  when "list"
    Trollop::options do
      opt :number,     "Number of issues to display",   :type => Integer, :default => 50
      # opt :q,   "Optional custom query id",      :type => Integer
      opt :q,   "Optional custom query id",      :type => String
    end
  else
    Trollop::die "Uknown command #{command}"
end

opts = global_options.merge(command_options)
YAML::load_file(opts[:filename]).each_pair { |name, default| opts[name.to_sym] ||= default } if File.exist?(opts[:filename])
Textgoeshere::Red.new(command, opts)

