set_proxy() {
    # 检查 Docker 是否安装
    local docker_installed=false
    if command -v docker &> /dev/null; then
        docker_installed=true
    else
        echo "Docker is not installed. Docker proxy configuration will be skipped."
    fi

    # 获取代理设置
    local proxy_mode=$(dconf read /system/proxy/mode)
    local autoconfig_url=$(dconf read /system/proxy/autoconfig-url | tr -d "'")
    local fixed_pac_url="https://xxx.xx.net/autoproxy"

    # 初始化代理主机和端口
    local proxy_host=""
    local proxy_port=""

    # 如果代理模式是'auto'，解析PAC文件
    if [ "$proxy_mode" = "'auto'" ]; then
        echo "Using auto proxy configuration from: $autoconfig_url"
        local pac_file_content=$(curl -s "${autoconfig_url}")
        local proxy_info=$(echo "$pac_file_content" | grep -oP 'PROXY\s+\K((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(:\d+)?')

        if [ -n "$proxy_info" ]; then
            proxy_host=$(echo "$proxy_info" | cut -d ':' -f 1)
            proxy_port=$(echo "$proxy_info" | cut -d ':' -f 2)
        else
            echo "No valid proxy found in PAC file."
            return 1
        fi
    elif [ -z "$proxy_mode" ] || [ "$proxy_mode" = "'none'" ]; then
        # 使用固定的PAC文件网址
        echo "No proxy configured. Using fixed PAC file from: $fixed_pac_url"
        local pac_file_content=$(curl -s "${fixed_pac_url}")
        local proxy_info=$(echo "$pac_file_content" | grep -oP 'PROXY\s+\K((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(:\d+)?')

        if [ -n "$proxy_info" ]; then
            proxy_host=$(echo "$proxy_info" | cut -d ':' -f 1)
            proxy_port=$(echo "$proxy_info" | cut -d ':' -f 2)
        else
            echo "No valid proxy found in fixed PAC file."
            return 1
        fi
    else
        # 手动获取默认的代理设置
        proxy_host=$(dconf read /system/proxy/http/host | tr -d "'")
        proxy_port=$(dconf read /system/proxy/http/port)
    fi

    # 设置终端代理
    export http_proxy="http://$proxy_host:$proxy_port"
    export https_proxy="http://$proxy_host:$proxy_port"

    # 输出终端代理设置
    echo "Setting terminal proxy to: http://$proxy_host:$proxy_port"
    echo "http_proxy set to: $http_proxy"
    echo "https_proxy set to: $https_proxy"

    # 配置 GitHub SSH 代理
    local ssh_config_file="$HOME/.ssh/config"
    if [ ! -f "$ssh_config_file" ]; then
        touch "$ssh_config_file"
    fi

    # 检查是否有针对 github.com 的配置
    if grep -q "Host github.com" "$ssh_config_file"; then
        # 检查是否已有代理设置
        if ! grep -q "ProxyCommand" "$ssh_config_file"; then
            echo "Adding SSH proxy configuration for GitHub."
            echo -e "Host github.com\n\tProxyCommand nc -X 5 -x $proxy_host:$proxy_port %h %p\n" >> "$ssh_config_file"
        else
            echo "SSH proxy configuration for GitHub already exists."
        fi
    else
        echo "Adding new SSH configuration for GitHub."
        echo -e "Host github.com\n\tProxyCommand nc -X 5 -x $proxy_host:$proxy_port %h %p\n" >> "$ssh_config_file"
    fi

    # 检查 Docker 代理配置目录
    if $docker_installed; then
        local docker_proxy_dir="/etc/systemd/system/docker.service.d"
        local docker_proxy_file="$docker_proxy_dir/http-proxy.conf"

        if [ ! -d "$docker_proxy_dir" ]; then
            echo "Docker proxy directory does not exist. Creating it..."
            sudo mkdir -p "$docker_proxy_dir"
        fi

        # 根据参数决定是否更新 Docker 代理配置
        if [[ $1 == "onlyshell" ]]; then
            echo "Skipping Docker proxy configuration update."
            return 0
        fi

        # 默认情况下强制更新 Docker 代理配置
        echo "Updating Docker proxy configuration..."

        # 创建或更新 Docker 代理配置文件
        sudo bash -c "cat <<EOF > $docker_proxy_file
[Service]
Environment=\"HTTP_PROXY=http://$proxy_host:$proxy_port/\"
Environment=\"HTTPS_PROXY=http://$proxy_host:$proxy_port/\"
EOF"

        # 重新加载并重启 Docker 服务
        sudo systemctl daemon-reload
        sudo systemctl restart docker

        echo "Docker proxy configured: http://$proxy_host:$proxy_port"
    else
        echo "Docker proxy configuration will be skipped."
    fi
}

