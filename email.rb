
require 'rubygems'
require 'postmark'

def usage
  puts 'Email a message using PostMark.'
  puts
  puts %|Usage: email.rb --postmark-key=... --to=you@example.com --from=me@example.com --subject='...' --body='...'|
  exit 1
end

def load_arg(name)
  found = ARGV.grep /^--#{name}=.+/
  return nil if found.empty?
  found.first.split('=').last
end

POSTMARK_API_KEY = load_arg('postmark-key') || usage
to = load_arg('to') || usage
from = load_arg('from') || usage
subject = load_arg('subject') || usage
body = load_arg('body') || usage

mail = Postmark::ApiClient.new(POSTMARK_API_KEY, secure: true)
mail.deliver(
  from: from,
  to: to,
  subject: subject,
  text_body: body
)
