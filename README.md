###Flowdock-Gitlab-Webhook-Receiver

- [Introduction](#introduction)
- [Installation](#installation)
- [Start](#start)

# Introduction

Catch Gitlab webhooks and send notification to your Flowodck inbox

# Installation

```

docker pull ryudoawaru/flowdock-gitlab-webhook

```

# Start

Prepare your [secret token](https://docs.gitlab.com/ce/user/project/integrations/webhooks.html#secret-token) for Gitlab webhook use.

```

docker run -d -e "RACK_ENV=production" -e "GITLAB_TOKEN=$xxxxoooxxx" --rm -p 3000:3000 ryudoawaru/flowdock-gitlab-webhook

```

Point your browser to http://YOUR-HOST-NAME:3000 to test if it starts successfully.

Register an new "Shortcut application" in [Developer Application](https://www.flowdock.com/oauth/applications) section of your Flowdock account settings.

In the Flowdock flow you want to subscribe notifications, add new source of the application you just registered and get the flow api token.

Use this flow api token and the secret token to register new webhook in your Gitlab repo, the URL pattern should be like 「http(s)://YOUR-HOST-NAME/FLOW-API-TOKEN.json」.

Test it!

# Support Trigger types

1.	Push
1.	Comments of Commit / Merge Request / Issue
1.	Issue
1.	Merge Request
1.	Build
1.	Pipeline