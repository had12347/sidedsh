#!/bin/bash

# 检查并安装所需的软件
function install_dependencies() {
    sudo apt-get update
    sudo apt-get install -y curl git jq wget htop tmux build-essential lz4 gcc unzip
}

# 安装Node.js和PM2
function install_nodejs_pm2() {
    curl -sL https://deb.nodesource.com/setup_14.x | sudo -E bash -
    sudo apt-get install -y nodejs
    sudo npm install -g pm2
}

# 安装Side节点
function install_node() {
    read -p "请输入节点名称: " NODE_NAME
    read -p "请输入节点的端口号: " SIDE_PORT

    # 设置环境变量
    echo "export MONIKER=${NODE_NAME}" >> $HOME/.bash_profile
    echo "export SIDE_PORT=${SIDE_PORT}" >> $HOME/.bash_profile
    source $HOME/.bash_profile

    # 下载并安装 Side binary
    cd $HOME
    rm -rf side
    git clone https://github.com/sideprotocol/side.git
    cd side
    git checkout v0.9.0
    make install

    # 配置并初始化应用
    sided config node tcp://localhost:${SIDE_PORT}657
    sided config keyring-backend os
    sided config chain-id grimoria-testnet-1
    sided init "$MONIKER" --chain-id grimoria-testnet-1

    # 下载 genesis 和 addrbook
    wget -O $HOME/.side/config/genesis.json https://server-5.itrocket.net/testnet/side/genesis.json
    wget -O $HOME/.side/config/addrbook.json https://server-5.itrocket.net/testnet/side/addrbook.json

    # 设置 seeds 和 peers
    SEEDS="9c14080752bdfa33f4624f83cd155e2d3976e303@side-testnet-seed.itrocket.net:45656"
    PEERS="bbbf623474e377664673bde3256fc35a36ba0df1@side-testnet-peer.itrocket.net:45656,8e7a1deab860a24d4649d124beb37ac8f8257264@[2a01:4f8:262:121c::2]:13556,d5519e378247dfb61dfe90652d1fe3e2b3005a5b@65.109.68.190:17456,7cfbb4742a91fc616bf8d64d05234892a7675ded@91.227.33.18:45656,637077d431f618181597706810a65c826524fd74@5.9.151.56:26356,027ef6300590b1ca3a2b92a274247e24537bd9c9@65.109.65.248:49656,fc350bf644f03278df11b8735727cc2ead4134c9@65.109.93.152:26786,e6575e39599afba59bbe3422284b22edfb1adafb@23.88.5.169:24656,0877bfe53645c830b21ab4098335b2061dac1efa@69.67.150.107:21396,fffd63269133a403cb7d15d8c3b2905b63c73b2a@185.225.191.149:26656"
    sed -i.bak -E "s|^seeds =.*$|seeds = \"$SEEDS\"|" $HOME/.side/config/config.toml
    sed -i.bak -E "s|^persistent_peers =.*$|persistent_peers = \"$PEERS\"|" $HOME/.side/config/config.toml

    # 设置自定义端口
    sed -i.bak -e "s%:1317%:${SIDE_PORT}317%g;
    s%:8080%:${SIDE_PORT}080%g;
    s%:9090%:${SIDE_PORT}090%g;
    s%:9091%:${SIDE_PORT}091%g;
    s%:8545%:${SIDE_PORT}545%g;
    s%:8546%:${SIDE_PORT}546%g;
    s%:6065%:${SIDE_PORT}065%g" $HOME/.side/config/app.toml

    sed -i.bak -e "s%:26658%:${SIDE_PORT}658%g;
    s%:26657%:${SIDE_PORT}657%g;
    s%:6060%:${SIDE_PORT}060%g;
    s%:26656%:${SIDE_PORT}656%g;
    s%^external_address = \"\"%external_address = \"$(wget -qO- eth0.me):${SIDE_PORT}656\"%;
    s%:26660%:${SIDE_PORT}660%g" $HOME/.side/config/config.toml

    # 配置 pruning
    sed -i -e "s/^pruning *=.*/pruning = \"custom\"/" $HOME/.side/config/app.toml
    sed -i -e "s/^pruning-keep-recent *=.*/pruning-keep-recent = \"100\"/" $HOME/.side/config/app.toml
    sed -i -e "s/^pruning-interval *=.*/pruning-interval = \"50\"/" $HOME/.side/config/app.toml

    # 创建服务文件
    sudo tee /etc/systemd/system/sided.service > /dev/null <<EOF
[Unit]
Description=Side node
After=network-online.target
[Service]
User=$USER
WorkingDirectory=$HOME/.side
ExecStart=$(which sided) start --home $HOME/.side
Restart=on-failure
RestartSec=5
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF

    # 重置并下载快照
    sided tendermint unsafe-reset-all --home $HOME/.side
    if curl -s --head https://server-5.itrocket.net/testnet/side/side_2024-08-06_401474_snap.tar.lz4 | head -n 1 | grep "200" > /dev/null; then
        curl https://server-5.itrocket.net/testnet/side/side_2024-08-06_401474_snap.tar.lz4 | lz4 -dc - | tar -xf - -C $HOME/.side
    else
        echo "没有找到快照"
    fi

    # 启用并启动服务
    sudo systemctl daemon-reload
    sudo systemctl enable sided
    sudo systemctl start sided

    echo "节点安装完成!"
}

# 创建钱包
function add_wallet() {
    read -p "请输入钱包名称: " WALLET_NAME
    sided keys add $WALLET_NAME
}

# 导入钱包
function import_wallet() {
    read -p "请输入钱包名称: " WALLET_NAME
    sided keys add $WALLET_NAME --recover
}

# 查看钱包地址余额
function check_balances() {
    read -p "请输入钱包地址: " WALLET_ADDRESS
    sided q bank balances $WALLET_ADDRESS
}

# 查看节点同步状态
function check_sync_status() {
    sided status | jq .SyncInfo
}

# 查看当前服务状态
function check_service_status() {
    pm2 list
}

# 运行日志查询
function view_logs() {
    pm2 logs sided
}

# 卸载节点
function uninstall_node() {
    read -p "请输入节点名称: " NODE_NAME
    pm2 delete $NODE_NAME
    cd ..
    rm -rf side
    sudo apt-get remove -y nodejs
    sudo npm uninstall -g pm2
    sudo systemctl stop sided
    sudo systemctl disable sided
    sudo rm /etc/systemd/system/sided.service
}

# 创建验证者
function add_validator() {
    read -p "请输入钱包名称: " WALLET_NAME
    read -p "请输入验证者的名称: " VALIDATOR_NAME
    sided tx staking create-validator \
        --amount 1000000uside \
        --from $WALLET_NAME \
        --commission-rate 0.1 \
        --commission-max-rate 0.2 \
        --commission-max-change-rate 0.01 \
        --min-self-delegation 1 \
        --pubkey $(sided tendermint show-validator) \
        --moniker "$VALIDATOR_NAME" \
        --identity "" \
        --chain-id grimoria-testnet-1 \
        --gas auto --gas-adjustment 1.5 --fees 1500uside \
        -y
}

# 给自己质押
function delegate_self_validator() {
    read -p "请输入钱包名称: " WALLET_NAME
    read -p "请输入质押金额（例如1000000uside）: " STAKE_AMOUNT
    sided tx staking delegate $(sided keys show $WALLET_NAME --bech val -a) $STAKE_AMOUNT --from $WALLET_NAME --chain-id grimoria-testnet-1 --gas auto --gas-adjustment 1.5 --fees 1500uside -y
}

# 主菜单
function main_menu() {
    while true; do
        clear
        echo "脚本以及教程由推特用户大赌哥 @y95277777 编写，免费开源，请勿相信收费"
        echo "============================Artela节点安装===================================="
        echo "节点社区 Telegram 群组: https://t.me/niuwuriji"
        echo "节点社区 Telegram 频道: https://t.me/niuwuriji"
        echo "节点社区 Discord 社群: https://discord.gg/GbMV5EcNWF"
        echo "退出脚本，请按键盘ctrl c退出即可"
        echo "请选择要执行的操作:"
        echo "1. 安装节点"
        echo "2. 创建钱包"
        echo "3. 导入钱包"
        echo "4. 查看钱包地址余额"
        echo "5. 查看节点同步状态"
        echo "6. 查看当前服务状态"
        echo "7. 运行日志查询"
        echo "8. 卸载节点"
        echo "9. 创建验证者"
        echo "10. 给自己质押"
        echo "0. 退出"

        read -p "请输入操作编号: " OPTION
        case $OPTION in
            1) install_node ;;
            2) add_wallet ;;
            3) import_wallet ;;
            4) check_balances ;;
            5) check_sync_status ;;
            6) check_service_status ;;
            7) view_logs ;;
            8) uninstall_node ;;
            9) add_validator ;;
            10) delegate_self_validator ;;
            0) exit ;;
            *) echo "无效的选项，请重新输入" ;;
        esac
        read -p "按回车键继续..."
    done
}

# 运行主菜单
main_menu
