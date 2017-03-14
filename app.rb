#frozen_string_literal: true
require 'rubygems'
require 'bundler'
RACK_ENV = ENV["RACK_ENV"] ||= "development" unless defined? RACK_ENV

require "sinatra/reloader" if RACK_ENV == 'development'

ROOT_DIR = File.dirname(__FILE__) + '/../' unless defined? ROOT_DIR

Bundler.setup
Bundler.require :default, :assets, RACK_ENV

class FlowdockGitlabWebhook < Sinatra::Base
  configure :development do
    register Sinatra::Reloader
  end

  STATUS_COLOR = {
    reopen: "green",
    reopened: "green",
    open: "green",
    opened: "green",
    close: "red",
    closed: "red",
    merge: "purple",
    merged: "purple"
  }

  helpers do
    def process_note(src, post)
      post[:event] = "discussion"
      tg = src.object_attributes
      case tg.noteable_type
      when "Commit"
        #built with thread together
        post[:thread] = {
          title: "#{src.project.path_with_namespace} commit #{src.object_attributes.commit_id[0..6]} commented",
          fields: [gen_field_hash('repository', gen_link(src.project.homepage, src.project.path_with_namespace))]
        }
        post[:title] = if tg.position #means comment on line of code
                         gen_link tg.url, "commented file #{tg.position.old_path}"
                       else
                         gen_link tg.url, "commented commit #{tg.commit_id[0..6]}"
                       end
        post[:body] = tg.note
        post[:external_thread_id] = gen_tid_of_commit_comments(tg.commit_id)
      when "MergeRequest"
        post[:title] = gen_link(tg.url, "commented")
        post[:body] = tg.note
        #also build thread if not created with the PR together
        mr = src.merge_request
        post[:external_thread_id] = gen_tid_of_merge_request(mr.id)
        #Since we can't get enough data as the PR webhook so just build simplified version
        post[:thread] = {
          title: "\##{mr.iid} #{mr.title}",
          external_url: "#{mr.source.homepage}/merge_requests/#{mr.iid}"
        }
      when "Issue"
        post[:title] = "#{src.user.userename} <a href='#{src.object_attributes.url}'>commented</a> on Gitlab"
        post[:body] = src.object_attributes.note
        post[:external_thread_id] = gen_tid_of_issue(src.issue.id)
        post[:thread] = {
          title: gen_title_of_issue(src.issue),
          body: src.issue.description
        }
      when "Snippet"
      else
      end
      post
    end

    def process_merge_request(src, post)
      ts = Time.parse(src.object_attributes.updated_at).localtime.strftime('on %b %d')
      lc = src.object_attributes.last_commit
      post[:title] = if src.object_attributes.action == "merge"
                       "merged at #{gen_link(lc.url, lc.id[0..6])} and closed #{ts}"
                     else
                       "#{src.object_attributes.action}ed #{ts}"
                     end
      post[:external_thread_id] = gen_tid_of_merge_request(src.object_attributes.id)
      post[:thread] = {
        title: "\##{src.object_attributes.iid} #{src.object_attributes.title}",
        external_url: src.object_attributes.url,
        status: gen_state_label_hash(src.object_attributes.state),
        fields: [gen_field_hash('repository', gen_link(src.project.homepage, src.project.path_with_namespace)), gen_field_hash('branch', gen_link_of_repo_and_branch(src.project.homepage, src.object_attributes.source_branch))]
      }
    end

    def process_push(src, api)
      # because we may have many commits in a push so we have to post many times
      branch_name = src.ref.gsub("refs/heads/", '')
      push_title = if src.before.to_i == 0 #means first time push of a branch
                   "Created branch #{branch_name} at #{src.project.path_with_namespace}"
                 else
                   "#{branch_name} at #{src.project.path_with_namespace} updated"
                 end
      external_thread_id = gen_tid_of_branch_commit(branch_name)
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
      #title of action/discussion
      post[:title] = "#{src.user.name} #{src.object_attributes.state} issue"
      post[:external_thread_id] = gen_tid_of_issue(src.object_attributes.id)
      post[:thread] = {
        title: gen_title_of_issue(src.object_attributes),
        fields: [gen_field_hash("repository", gen_link(src.object_attributes.url, src.project.path_with_namespace) )],
        body: src.object_attributes.description,
        external_url: src.object_attributes.url,
        status: gen_state_label_hash(src.object_attributes.state)
      }
      post
    end

    def gen_link_of_repo_and_branch(repo_base_url, branch_name)
      gen_link "#{repo_base_url}/tree/#{branch_name}", branch_name
    end

    def gen_link(href, text)
      sprintf '<a href="%s">%s</a>', href, text
    end

    def gen_tid_of_commit_comments(commit_id)
      "commit-#{commit_id}-comments"
    end

    def gen_tid_of_issue(id)
      "issue-#{id}"
    end

    def gen_tid_of_merge_request(id)
      "pull-req-#{id}"
    end

    def gen_tid_of_branch_commit(branch_name)
      "commits-of-#{branch_name}"
    end

    def gen_title_of_issue(issue)
      "\##{issue.id}: #{issue.title}"
    end

    def gen_state_label_hash(state)
      {color: STATUS_COLOR[state.to_s.to_sym], value: state}
    end

    def gen_field_hash(label, value)
      {label: label, value: value}
    end

  end

  post '/:flow_api_token.json' do
    token = request.env['HTTP_X_GITLAB_TOKEN']
    @body = request.body.read
    puts @body
    @flow_api = Flowdock::Client.new(flow_token: params[:flow_api_token])
    @jobj = JSON.parse(@body, object_class: OpenStruct)
    @hobj = JSON.parse(@body)
    case @jobj.object_kind
    when "issue", "note", "merge_request"
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
