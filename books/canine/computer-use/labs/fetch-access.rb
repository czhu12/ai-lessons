# Writes what the labs need to reach one agent computer into labs/.secrets/ (git-ignored):
#   kubeconfig    the computer's cluster, as Canine connects to it
#   ssh_key       the computer's generated SSH key (the unattended install put its public half in authorized_keys)
#   computer.env  NAMESPACE, VM and COMPUTER_ID
# Run from the Canine repo:   bin/rails runner <labs>/fetch-access.rb <computer id>
computer = AgentComputer.find(ARGV.fetch(0))
connection = K8::Connection.new(computer.cluster, computer.user)
secrets = File.join(__dir__, ".secrets")
FileUtils.mkdir_p(secrets, mode: 0o700)

kubeconfig = connection.kubeconfig
kubeconfig = JSON.parse(kubeconfig) if kubeconfig.is_a?(String)
kubeconfig = K8::Kubeconfig.apply_tls_settings(kubeconfig, computer.cluster.skip_tls_verify)
File.write(File.join(secrets, "kubeconfig"), kubeconfig.to_yaml, perm: 0o600)
File.write(File.join(secrets, "ssh_key"), computer.ssh_private_key, perm: 0o600)
File.write(File.join(secrets, "computer.env"), <<~ENV, perm: 0o600)
  COMPUTER_ID=#{computer.id}
  NAMESPACE=#{computer.namespace}
  VM=#{computer.name}
ENV
puts "Wrote kubeconfig, ssh_key and computer.env for #{computer.name} (#{computer.status}) to #{secrets}"
