# Use the official Amazon Linux 2023 container image
FROM amazonlinux:2023

# Update packages and install necessary tools
RUN dnf update -y && \
    dnf install -y sudo openssh-server passwd && \
    dnf clean all

# Create a non-root user (ec2-user) with a home directory and bash shell
RUN useradd -m -s /bin/bash ec2-user && \
    echo "ec2-user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set up SSH server: create the directory for sshd runtime files
RUN mkdir -p /var/run/sshd

# Set up SSH authorized_keys for ec2-user
RUN mkdir -p /home/ec2-user/.ssh && \
    chmod 700 /home/ec2-user/.ssh
COPY --chown=ec2-user:ec2-user id_rsa.pub /home/ec2-user/.ssh/authorized_keys
RUN chown -R ec2-user:ec2-user /home/ec2-user/.ssh && \
    chmod 600 /home/ec2-user/.ssh/authorized_keys

# Generate SSH host keys
RUN ssh-keygen -A

# Copy the custom entrypoint script into the image and ensure it is executable
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose the SSH port
EXPOSE 22

# Set the entrypoint to our custom script and the default command to run sshd in foreground.
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/sbin/sshd", "-D"]
