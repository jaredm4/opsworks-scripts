
require 'rubygems'
require 'json'

def usage
  puts 'Runs recipes on all online instances in a layer, and reports their success via shell status_code.'
  puts 'Usage: execute-instance-recipes.rb <stack-id> <layer-id> <recipes> [\'custom-json\']'
  puts
  puts 'stack-id:    The OpsWorks Stack ID where the layer is located.'
  puts 'layer-id:    The OpsWorks Layer ID where the instances are located.'
  puts 'recipes:     JSON array of recipes to run, in the format of: \'["cookbook::recipe"]\'. Wrap in single quotes.'
  puts 'custom-json: Custom JSON to use for the deployment. Wrap in single quotes.'
  exit 1
end

unless `which aws`
  puts 'awscli not found!'
  usage
end

if ARGV.length < 3
  usage
end

stack_id = ARGV[0]
layer_id = ARGV[1]
recipes = ARGV[2]
custom_json = ARGV[3].nil? ? '' : ARGV[3]

# all instances in layer
instances_command = %|aws opsworks describe-instances --layer-id #{layer_id}|
instances = JSON.parse(`#{instances_command}`)['Instances']
if instances.empty?
  puts "Failed to load instances."
  puts "Command: #{instances_command}"
  exit 1
end
# that are online
instances.delete_if {|x| x['Status'] != 'online' }
# pluck their ids
instance_ids = instances.collect {|x| x['InstanceId'] }
print 'Found online instances: '
p instance_ids


# kick off the publish recipe
publish_command = %|aws opsworks create-deployment --stack-id #{stack_id} --instance-ids #{instance_ids.join(' ')} --command='{"Name": "execute_recipes", "Args": {"recipes": #{recipes}}}'|
unless custom_json.empty?
  publish_command += %| --custom-json='#{custom_json}'|
end
results = `#{publish_command}`
publish_id = JSON.parse(results)['DeploymentId']
if publish_id.empty?
  puts "Failed to create publish recipe deploy."
  puts "Command: #{publish_command}"
  exit 1
end
print 'Created publish deployment, received ID of: '
p publish_id

status_command = %|aws opsworks describe-deployments --deployment-ids #{publish_id}|
start_time = Time.now
max_time = start_time + 3600
while Time.now < max_time
  # sleep first to give it time to run
  sleep 5
  print "(#{(Time.now - start_time).round} secs) Checking status... "
  results = `#{status_command}`
  unless results.empty?
    status = JSON.parse(results)['Deployments'][0]['Status']

    if status == 'successful'
      puts "deployment was successful."
      exit 0
    elsif status == 'failed'
      puts "deployment failed!"
      exit 1
    else
      puts status
    end
  end
end

puts "Deployment '#{publish_id}' on instances #{instance_ids} took over an hour, giving up."
exit 1
