require File.join(File.dirname(__FILE__), 'app.rb')

map '/' do
  run FlowdockGitlabWebhook
end
