#!/bin/bash
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y

sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo groupadd docker

sudo usermod -aG docker $USER

newgrp docker

cat << EOF > script.sql

USE BlackScreen;

CREATE TABLE Enderecos (
    Id_Endereco INT AUTO_INCREMENT PRIMARY KEY,
    Cep VARCHAR(9),
    Pais VARCHAR(255),
    Cidade VARCHAR(255),
    UF VARCHAR(255),
    Logradouro VARCHAR(255),
    Numero INT,
    Latitude DECIMAL(10,8),
    Longitude DECIMAL(11,8),
    Bairro VARCHAR(100),
    Complemento VARCHAR(200)
);

CREATE TABLE Empresa (
    Id_Empresa INT AUTO_INCREMENT PRIMARY KEY ,
    Nome_Empresa VARCHAR(255),
    Cnpj VARCHAR(255) UNIQUE,
    Fk_Endereco INT,
    CONSTRAINT FK_Empresa_Endereco
        FOREIGN KEY (Fk_Endereco) REFERENCES Enderecos(Id_Endereco)
);

CREATE TABLE Cargo (
    Id_Cargo INT AUTO_INCREMENT PRIMARY KEY,
    Nome_Cargo VARCHAR(255) NOT NULL,
    Fk_Empresa INT,
    CONSTRAINT FK_Cargo_Empresa
        FOREIGN KEY (Fk_Empresa) REFERENCES Empresa(Id_Empresa)
);

CREATE TABLE Usuario (
    Id_Usuario INT AUTO_INCREMENT PRIMARY KEY,
    Nome VARCHAR(255),
    Email VARCHAR(255) UNIQUE,
    Senha VARCHAR(255),
    Fk_Empresa INT,
    Fk_Cargo INT, 
    CONSTRAINT FK_Usuario_Empresa
        FOREIGN KEY (Fk_Empresa) REFERENCES Empresa(Id_Empresa),
    CONSTRAINT FK_Usuario_Cargo 
        FOREIGN KEY (Fk_Cargo) REFERENCES Cargo(Id_Cargo)
);

CREATE TABLE Caixa (
    Id_Caixa INT AUTO_INCREMENT PRIMARY KEY,  
    codigoCaixa VARCHAR(12) UNIQUE,
    Fk_Endereco_Maquina INT,
    Fk_Empresa INT,
    CONSTRAINT FK_Caixa_Endereco
        FOREIGN KEY (Fk_Endereco_Maquina) REFERENCES Enderecos(Id_Endereco),
    CONSTRAINT FK_Caixa_Empresa
        FOREIGN KEY (Fk_Empresa) REFERENCES Empresa(Id_Empresa)
);

CREATE TABLE Componentes (
    Id_Componente INT AUTO_INCREMENT PRIMARY KEY not null,
    Nome_Componente VARCHAR(255) not null,
    Fk_Caixa INT not null,
    Unidade VARCHAR(20),
    CONSTRAINT FK_Componentes_Caixa
        FOREIGN KEY (Fk_Caixa) REFERENCES Caixa(Id_Caixa) 
);

CREATE TABLE Parametros (
    Id_Parametro INT AUTO_INCREMENT PRIMARY KEY,
    Valor_Parametrizado INT not null,
    Fk_Componente INT,
    CONSTRAINT FK_Parametros_Componentes
        FOREIGN KEY (Fk_Componente) REFERENCES Componentes(Id_Componente)
);

CREATE TABLE Permissao (
    Id_Permissao INT AUTO_INCREMENT PRIMARY KEY,
    Nome_Permissao VARCHAR(255) NOT NULL UNIQUE,
    Descricao_Permissao VARCHAR(255)
);

CREATE TABLE CargoPermissao (
    Fk_Cargo INT NOT NULL,
    Fk_Permissao INT NOT NULL,
    CONSTRAINT PK_CargoPermissao 
        PRIMARY KEY (Fk_Cargo, Fk_Permissao),
    CONSTRAINT FK_CargoPermissao_Cargo
        FOREIGN KEY (Fk_Cargo) REFERENCES Cargo(Id_Cargo),
    CONSTRAINT FK_CargoPermissao_Permissao
        FOREIGN KEY (Fk_Permissao) REFERENCES Permissao(Id_Permissao)
);

INSERT INTO Enderecos (Cep, Pais, Cidade, UF, Logradouro, Numero, Latitude, Longitude, Bairro, Complemento) VALUES
('01001-000', 'Brasil', 'São Paulo', 'SP', 'Av. Paulista', 1000, -7.948196, -34.890172, 'Bela Vista', 'Térreo'),
('02020-000', 'Brasil', 'São Paulo', 'SP', 'Rua Vergueiro', 200, -7.937091, -34.857388, 'Liberdade', 'Sala 2'),
('03030-000', 'Brasil', 'Curitiba', 'PR', 'Rua XV de Novembro', 300, -7.954592, -34.952316, 'Centro', NULL),
('04040-000', 'Brasil', 'Rio de Janeiro', 'RJ', 'Av. Atlântica', 400, -5.853801, -36.210938, 'Copacabana', 'Quiosque 5');

INSERT INTO Empresa (Nome_Empresa, Cnpj, Fk_Endereco) VALUES
('BlackScreen', '12345678000199', 1),
('SafeBank Systems', '98765432000177', 2),
('CaixaProtegida Ltda', '11122233000155', 3);

INSERT INTO Cargo (Nome_Cargo, Fk_Empresa) VALUES
('Administrador', 1),
('Administrador', 2),
('Administrador', 3);

INSERT INTO Usuario (Nome, Senha, Email, Fk_Empresa, Fk_Cargo) VALUES
('Pedro Amaral', 'senha123', 'pedro@blackscreen.com', 1, 1),
('Vitorio Bearari', 'senha456', 'vitorio@safebank.com', 2, 2),
('Hanieh Ashouri', 'senha789', 'hanieh@caixaprotegida.com', 3, 3);

INSERT INTO Caixa (codigoCaixa, Fk_Empresa, Fk_Endereco_Maquina) VALUES
('CX001', 1, 1),
('CX002', 1, 2),
('CX101', 2, 3),
('CX201', 3, 4);

INSERT INTO Componentes (Nome_Componente, Unidade, Fk_Caixa) VALUES
('CPU', '%', 1),
('Disco', '%', 1),
('Memória', '%', 2),
('CPU', '%', 3),
('Memória', '%', 4);

INSERT INTO Parametros (Valor_Parametrizado, Fk_Componente) VALUES
(75, 1),
(60, 2),
(80, 3),
(55, 4),
(90, 5);

EOF
docker pull mysql:8.0.37

CONTAINER_NAME="BlackScreen"

if [ ! "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
    docker run --name BlackScreen \
  -p 3306:3306 \
  -e MYSQL_ROOT_PASSWORD=rootpassword \
  -e MYSQL_DATABASE=BlackScreen \
  -e MYSQL_USER=usuario \
  -e MYSQL_PASSWORD='senha123@' \
  -v ./script.sql:/docker-entrypoint-initdb.d/init.sql:ro \
  -d mysql:8.0.37
fi


