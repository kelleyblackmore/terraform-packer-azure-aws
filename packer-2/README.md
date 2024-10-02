ansible-playbook -i 3.235.25.254, -u ec2-user --private-key ec2_rhel9.pem --extra-vars 'ansible_python_interpreter=/usr/bin/python3' playbook.yml


ansible-playbook -i 98.84.11.76, -u ec2-user --private-key ~/.ssh/mac-test.pem playbook.yml