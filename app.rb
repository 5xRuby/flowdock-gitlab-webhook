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
    def process_note(src, post)
      post[:event] = "discussion"
      tg = src.object_attributes
      case tg.noteable_type
      when "Commit"
        post[:thread] = {
          title: "#{src.project.path_with_namespace} commit #{src.object_attributes.commit_id[0..6]} commented",
          fields: [{
            label: 'repository',
            value: "<a href='#{src.project.homepage}'>#{src.project.path_with_namespace}</a>"
          }]
        }
        cat = Time.parse(src.object_attributes.created_at)
        post[:title] = "<a href='#{src.object_attributes.url}'>commented #{src.object_attributes.position.old_path} at #{cat.localtime.strftime("%Y/%m/%d %H:%M")}</a>"
        post[:body] = src.object_attributes.note
        post[:external_thread_id] = "commit-#{src.object_attributes.commit_id}-comments"
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

    def process_merge_request(src, post)
      tu = Time.parse(src.object_attributes.updated_at).localtime
      post[:title] = "#{src.object_attributes.state} on #{tu.strftime('%b at %H:%m')}"
      post[:external_thread_id]
      post[:thread] = {
        title: "\##{src.object_attributes.iid} #{src.object_attributes.title}",
        external_url: src.object_attributes.url,
        status: {color: STATUS_COLOR[src.object_attributes.action.to_s.to_sym], value: src.object_attributes.action},
        fields: [{
          label: 'repository',
          value: gen_link(src.project.homepage, src.project.path_with_namespace)
        },{
          label: 'branch',
          value: gen_link_of_repo_and_branch(src.project.homepage, src.object_attributes.source_branch)
        }]
      }
    end

    def gen_link_of_repo_and_branch(repo_base_url, branch_name)
      "#{repo_base_url}/tree/#{branch_name}"
    end

    def gen_link(href, text)
      sprintf '<a href="%s">%s</a>', href, text
    end

    def gen_tid_of_issue(id)
      "issue-#{id}"
    end

    def gen_title_of_issue(issue)
      "\##{issue.id}: #{issue.title}"
    end

    def process_push(src, api)
      # because we may have many commits in a push so we have to post many times
      branch_name = src.ref.gsub("refs/heads/", '')
      push_title = if src.before.to_i == 0 #means first time push of a branch
                   "Created branch #{branch_name} at #{src.project.path_with_namespace}"
                 else
                   "#{branch_name} at #{src.project.path_with_namespace} updated"
                 end
      external_thread_id = "commits-of-#{branch_name}"
      branch_url = src.project.web_url + "/tree/#{branch_name}"
      post ={
        event: "activity",
        author: {
          name: src.user_name,
          avatar: src.user_avatar
        },
        thread: {
          title: push_title,
          external_url: branch_url
        }
      }
      src.commits.each do |commit|
        post[:title] = "<a href='#{commit.url}'>#{commit.id[0..6]}</a> #{commit.message}"
        post[:external_thread_id] = external_thread_id
        api.post_to_thread post
      end
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

  post '/:flow_api_token.json' do
    token = request.env['HTTP_X_GITLAB_TOKEN']
    @body = request.body.read
    #puts "############REQUEST BODY###################"
    puts @body
    #puts "############REQUEST BODY###################"
    @flow_api = Flowdock::Client.new(flow_token: params[:flow_api_token])
    @jobj = JSON.parse(@body, object_class: OpenStruct)
    @hobj = JSON.parse(@body)

    case @jobj.object_kind
    when "issue", "note"#, "merge_request"
      @post = {
        event: "activity",
        author: {name: @jobj.user.name, avatar: @jobj.user.avatar_url}
      }
      send "process_#{@jobj.object_kind}", @jobj, @post
      @flow_api.post_to_thread @post if @post
    when "push"
      process_push @jobj, @flow_api
    end
    return {status: :ok}.to_json
  end
end
