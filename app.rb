#frozen_string_literal: true
require 'rubygems'
require 'bundler'
RACK_ENV = ENV["RACK_ENV"] ||= "development" unless defined? RACK_ENV

require "sinatra/reloader" if RACK_ENV == 'development'

ROOT_DIR = File.dirname(__FILE__) + '/../' unless defined? ROOT_DIR

Bundler.setup
Bundler.require :default, :assets, RACK_ENV

#$LOAD_PATH << File.expand_path(File.join(ROOT_DIR, 'app/models'))
#$LOAD_PATH << File.expand_path(File.join(ROOT_DIR, 'lib/'))

#set :bind, '0.0.0.0'

class FlowdockGitlabWebhook < Sinatra::Base
  configure :development do
    register Sinatra::Reloader
  end

  STATUS_COLOR = {
    reopen: "green",
    open: "green",
    close: "red",
    merge: "purple"
  }

  helpers do
    def process_tag
    end

    def process_push
    end

    def process_note(src, post)
      post[:event] = "discussion"
      tg = src.object_attributes
      case tg.noteable_type
      when "Commit"
      when "MergeRequest"
      when "Issue"
        post[:title] = "#{src.user.userename} <a href='#{src.object_attributes.url}'>commented</a> on Gitlab"
        post[:body] = src.object_attributes.note
        post[:external_thread_id] = gen_tid_of_issue(src.issue.id)
      when "Snippet"
      else
      end
      post
    end

    def process_merge_request
    end

    def gen_tid_of_issue(id)
      "issue-#{id}"
    end

    def gen_title_of_issue(issue)
      "\##{issue.id}: #{issue.title}"
    end

    def process_push(src, post)

    end

    def process_issue(src, post)
      #這個 title 是小標
      post[:title] = "#{src.user.name} #{src.object_attributes.state} issue"
      post[:external_thread_id] = gen_tid_of_issue(src.object_attributes.id)
      #post[:thread_id] = gen_tid_of_issue(src.object_attributes.id)
      post[:thread] = {
        #id: gen_tid_of_issue(src.object_attributes.id),
        #這個 title 才是大標題
        title: gen_title_of_issue(src.object_attributes),
        fields: [{
          label: "repository",
          value: "<a href='#{src.object_attributes.url}'>#{src.project.path_with_namespace}</a>"
        }],
        body: src.object_attributes.description,
        external_url: src.object_attributes.url,
        status: {color: STATUS_COLOR[src.object_attributes.action.to_s.to_sym], value: src.object_attributes.action}
      }
      post
    end
  end

  post '/:flow_api_token' do
    token = request.env['HTTP_X_GITLAB_TOKEN']
    @body = request.body.read
    #puts "############REQUEST BODY###################"
    puts @body
    #puts "############REQUEST BODY###################"
    @flow_api = Flowdock::Client.new(flow_token: params[:flow_api_token])
    @jobj = JSON.parse(@body, object_class: OpenStruct)
    @hobj = JSON.parse(@body)

    @post = {
      event: "activity",
      author: {name: @jobj.user.name, avatar: @jobj.user.avatar_url}
    }

    if %w{issue note}.include? @jobj.object_kind
      send "process_#{@jobj.object_kind}", @jobj, @post
      @flow_api.post_to_thread @post
    end
  end
end