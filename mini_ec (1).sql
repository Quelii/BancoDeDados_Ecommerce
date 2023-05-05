-- phpMyAdmin SQL Dump
-- version 5.2.0
-- https://www.phpmyadmin.net/
--
-- Host: 127.0.0.1
-- Tempo de geração: 01-Maio-2023 às 04:20
-- Versão do servidor: 10.4.25-MariaDB
-- versão do PHP: 7.4.30

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Banco de dados: `mini_ec`
--

DELIMITER $$
--
-- Procedimentos
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `proc_carga_carrinho` (`v_sessao` VARCHAR(32), `v_id_prod` INT, `v_qtd` INT, OUT `resposta` VARCHAR(50))   main: begin
        DECLARE v_qtd_livre int;
        DECLARE v_preco_venda decimal(10,2);
        
        DECLARE cod_erro CHAR(5) DEFAULT '00000';
	DECLARE msg TEXT;
        DECLARE linha INT;
        
		DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    	BEGIN
	      GET DIAGNOSTICS CONDITION 1
	      cod_erro = RETURNED_SQLSTATE, msg = MESSAGE_TEXT;
      END;
      	
    
    select estoque_Livre into v_qtd_livre from estoque
    where id_produto=v_id_prod;
    
    select v_qtd_livre;

    IF v_qtd>v_qtd_livre then
    	SET resposta='Quantidade Indisponivel';
    LEAVE main;
	END IF;
    

    select preco_venda into v_preco_venda from produto
    where id_produto=v_id_prod;
    

    START TRANSACTION;
   
    insert into carrinho_compras values 
      (md5(v_sessao),v_id_prod,v_qtd,v_preco_venda,0,v_qtd*v_preco_venda,now());
	
   
   update estoque set estoque_livre=estoque_livre-v_qtd,
                      estoque_reservado=estoque_reservado+v_qtd
	where id_produto=v_id_prod;
  


 IF cod_erro = '00000' THEN
    	  GET DIAGNOSTICS linha = ROW_COUNT;
		  SET resposta = CONCAT('Atualizacao com Sucesso  = ',linha);
          commit;
	ELSE
		SET resposta = CONCAT('Erro na atualizacao, error = ',cod_erro,', message = ',msg);
        rollback;
  END IF;
	
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `proc_carrinho_compras` (IN `p_sessao` VARCHAR(32))   BEGIN

  INSERT INTO carrinho_compras (sessao, id_produto, qtd, val_unit, desconto, total, data_hora_sessa)
    SELECT p.sessao, pi.id_produto, pi.qtd, p.val_unit, p.desconto, pi.total, NOW()
    FROM pedidos_itens pi
    INNER JOIN pedidos p ON p.num_pedido = pi.num_pedido
    WHERE p.sessao = p_sessao;


END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `PROC_FAT_PEDIDO` (IN `p_num_pedido` INT)   BEGIN

    DECLARE v_total_pedido DECIMAL(10,2);
    DECLARE v_valor_pago DECIMAL(10,2);
    DECLARE v_troco DECIMAL(10,2);
	DECLARE total DECIMAL(10,2);
    
    -- Obter o valor total do pedido
    SELECT total INTO v_total_pedido FROM pedidos WHERE num_pedido = p_num_pedido;

    -- Obter o valor total pago pelo cliente
    SELECT SUM(total_pedido) INTO v_valor_pago FROM pedidos WHERE num_pedido = p_num_pedido;

    -- Calcular o troco (se houver)
    IF v_valor_pago > v_total_pedido THEN
        SET v_troco = v_valor_pago - v_total_pedido;
    ELSE
        SET v_troco = 0;
    END IF;

    START TRANSACTION;

    -- Subtrair a quantidade vendida do estoque
    UPDATE estoque e, produto p
    INNER JOIN pedido_itens pi ON p.id_produto = pi.id_produto
    SET e.estoque_total = e.estoque_total - pi.qtd
    WHERE pi.num_pedido = p_num_pedido;

    -- Atualizar o status do pedido para "Faturado"
    UPDATE pedidos SET status_ped = 'Faturado' WHERE num_pedido = p_num_pedido;

    COMMIT;

    -- Imprimir o comprovante do pedido
    SELECT CONCAT('Pedido nº ', num_pedido, ' - Total: R$ ', total, ' - Valor pago: R$ ', v_valor_pago, ' - Troco: R$ ', v_troco) AS comprovante FROM pedidos WHERE num_pedido = p_num_pedido;

END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `PROC_FECHA_CARRINHO` (IN `p_sessao` VARCHAR(32))   BEGIN
    DECLARE v_num_pedido INT;
    
    START TRANSACTION;

    -- Obter os valores totais do carrinho
    SELECT SUM(total) AS total, SUM(qtd) AS qtd FROM carrinho_compras WHERE sessao = p_sessao AND status_ped = 'A';

    -- Inserir um novo pedido com os valores totais do carrinho
    INSERT INTO pedidos (total_pedido, status_ped, data_pedido) VALUES (total_pedido, 'A', NOW());

    -- Armazenar o número do pedido gerado
    SET v_num_pedido = LAST_INSERT_ID();

    -- Inserir os itens do carrinho no pedido
    INSERT INTO pedido_itens (num_pedido, id_produto, qtd, val_unit, total)
    SELECT v_num_pedido, id_produto, qtd, val_unit, total FROM carrinho_compras WHERE sessao = p_sessao AND status_ped = 'A';

    -- Subtrair a quantidade vendida do estoque
    UPDATE estoque e
    INNER JOIN carrinho_compras c ON e.id_produto = c.id_produto
    SET e.estoque_total = e.estoque_total - c.qtd
    WHERE c.sessao = p_sessao AND c.status_ped = 'A';

    -- Atualizar o status do carrinho para 'Fechado'
    UPDATE carrinho_compras SET status_ped = 'F', data_hora_sessa = NOW() WHERE sessao = p_sessao AND status_ped = 'A';

    COMMIT;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Estrutura da tabela `carrinho_compras`
--

CREATE TABLE `carrinho_compras` (
  `sessao` varchar(32) NOT NULL,
  `id_produto` int(11) NOT NULL,
  `qtd` int(11) NOT NULL,
  `val_unit` decimal(10,2) NOT NULL,
  `desconto` decimal(10,2) NOT NULL,
  `total` decimal(10,2) NOT NULL,
  `data_hora_sessa` datetime NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- --------------------------------------------------------

--
-- Estrutura da tabela `categorias`
--

CREATE TABLE `categorias` (
  `id_categoria` int(11) NOT NULL,
  `descricao` varchar(50) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

--
-- Extraindo dados da tabela `categorias`
--

INSERT INTO `categorias` (`id_categoria`, `descricao`) VALUES
(1, 'JOGOS'),
(2, 'ELETRÔNICOS'),
(3, 'SOM'),
(4, 'ELETRODOMÉSTICOS'),
(5, 'JOGOS'),
(6, 'ELETRÔNICOS'),
(7, 'SOM'),
(8, 'ELETRODOMÉSTICOS'),
(9, 'JOGOS'),
(10, 'ELETRÔNICOS'),
(11, 'SOM'),
(12, 'ELETRODOMÉSTICOS');

-- --------------------------------------------------------

--
-- Estrutura da tabela `cidades`
--

CREATE TABLE `cidades` (
  `id_cidade` int(11) NOT NULL,
  `nome_cidade` varchar(70) NOT NULL,
  `cod_mun` char(7) NOT NULL,
  `cod_uf` tinyint(4) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

--
-- Extraindo dados da tabela `cidades`
--

INSERT INTO `cidades` (`id_cidade`, `nome_cidade`, `cod_mun`, `cod_uf`) VALUES
(1, '', '', 0);

-- --------------------------------------------------------

--
-- Estrutura da tabela `clientes`
--

CREATE TABLE `clientes` (
  `id_cliente` int(11) NOT NULL,
  `nome` varchar(32) NOT NULL,
  `sobrenome` varchar(32) NOT NULL,
  `email` varchar(60) NOT NULL,
  `senha` varchar(32) NOT NULL,
  `data_nasc` date NOT NULL,
  `data_cadastro` datetime NOT NULL,
  `ult_acesso` datetime DEFAULT NULL,
  `ult_compra` datetime DEFAULT NULL,
  `situacao` enum('A','B') NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- --------------------------------------------------------

--
-- Estrutura da tabela `cliente_endereco`
--

CREATE TABLE `cliente_endereco` (
  `id_endereco` int(11) NOT NULL,
  `id_cliente` int(11) NOT NULL,
  `tipo` enum('P','A') NOT NULL,
  `endereco` varchar(60) NOT NULL,
  `numero` varchar(10) NOT NULL,
  `bairro` varchar(30) NOT NULL,
  `cep` varchar(8) NOT NULL,
  `id_cidade` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- --------------------------------------------------------

--
-- Estrutura da tabela `cond_pagto`
--

CREATE TABLE `cond_pagto` (
  `id_pagto` int(11) NOT NULL,
  `descricao` varchar(50) NOT NULL,
  `tipo` enum('C','D','B') NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

--
-- Extraindo dados da tabela `cond_pagto`
--

INSERT INTO `cond_pagto` (`id_pagto`, `descricao`, `tipo`) VALUES
(1, '3 X', 'C'),
(2, '3 X', 'C');

-- --------------------------------------------------------

--
-- Estrutura da tabela `cond_pagto_det`
--

CREATE TABLE `cond_pagto_det` (
  `id_pagto` int(11) NOT NULL,
  `parcela` int(11) NOT NULL,
  `percentual` decimal(10,2) NOT NULL,
  `dias` int(11) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

--
-- Extraindo dados da tabela `cond_pagto_det`
--

INSERT INTO `cond_pagto_det` (`id_pagto`, `parcela`, `percentual`, `dias`) VALUES
(1, 1, '100.00', 1),
(1, 1, '100.00', 1),
(2, 1, '100.00', 1);

-- --------------------------------------------------------

--
-- Estrutura da tabela `estoque`
--

CREATE TABLE `estoque` (
  `id_produto` int(11) NOT NULL,
  `estoque_total` int(11) NOT NULL,
  `estoque_livre` int(11) DEFAULT NULL,
  `estoque_reservado` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

--
-- Extraindo dados da tabela `estoque`
--

INSERT INTO `estoque` (`id_produto`, `estoque_total`, `estoque_livre`, `estoque_reservado`) VALUES
(1, 100, 100, 0),
(2, 100, 100, 0),
(3, 100, 100, 0),
(4, 100, 100, 0),
(5, 100, 100, 0),
(6, 100, 100, 0),
(7, 100, 100, 0),
(8, 100, 100, 0),
(9, 100, 100, 0),
(10, 100, 100, 0),
(11, 100, 100, 0),
(12, 100, 100, 0),
(1, 100, 100, 0),
(2, 100, 100, 0),
(3, 100, 100, 0),
(4, 100, 100, 0),
(5, 100, 100, 0),
(6, 100, 100, 0),
(7, 100, 100, 0),
(8, 100, 100, 0),
(9, 100, 100, 0),
(10, 100, 100, 0),
(11, 100, 100, 0),
(12, 100, 100, 0);

-- --------------------------------------------------------

--
-- Estrutura da tabela `fabricantes`
--

CREATE TABLE `fabricantes` (
  `id_fabricante` int(11) NOT NULL,
  `nome_fabricante` varchar(50) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

--
-- Extraindo dados da tabela `fabricantes`
--

INSERT INTO `fabricantes` (`id_fabricante`, `nome_fabricante`) VALUES
(1, 'FABR JOGOS'),
(2, 'FABR ELETR.'),
(3, 'FABR. SOM'),
(4, 'FABR ELE.DOMES'),
(5, 'FABR JOGOS'),
(6, 'FABR ELETR.'),
(7, 'FABR. SOM'),
(8, 'FABR ELE.DOMES'),
(9, 'FABR JOGOS'),
(10, 'FABR ELETR.'),
(11, 'FABR. SOM'),
(12, 'FABR ELE.DOMES'),
(13, 'FABR JOGOS'),
(14, 'FABR ELETR.'),
(15, 'FABR. SOM'),
(16, 'FABR ELE.DOMES');

-- --------------------------------------------------------

--
-- Estrutura da tabela `nf_itens`
--

CREATE TABLE `nf_itens` (
  `num_nota` int(11) NOT NULL,
  `id_produto` int(11) NOT NULL,
  `qtd` int(11) NOT NULL,
  `val_unit` decimal(10,2) NOT NULL,
  `desconto` decimal(10,2) NOT NULL,
  `total` decimal(10,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- --------------------------------------------------------

--
-- Estrutura da tabela `nf_obs`
--

CREATE TABLE `nf_obs` (
  `num_nota` int(11) NOT NULL,
  `obs` varchar(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- --------------------------------------------------------

--
-- Estrutura da tabela `nota_fiscal`
--

CREATE TABLE `nota_fiscal` (
  `num_nota` int(11) NOT NULL,
  `num_ped_ref` int(11) NOT NULL,
  `id_cliente` int(11) NOT NULL,
  `id_endereco` int(11) NOT NULL,
  `id_pagto` int(11) NOT NULL,
  `total_prod` decimal(10,2) DEFAULT NULL,
  `total_frete` decimal(10,2) DEFAULT NULL,
  `total_desc` decimal(10,2) DEFAULT NULL,
  `total_nf` decimal(10,2) DEFAULT NULL,
  `data_nf` datetime NOT NULL,
  `status_nf` enum('N','C','D') DEFAULT NULL,
  `id_user` varchar(50) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- --------------------------------------------------------

--
-- Estrutura da tabela `pedidos`
--

CREATE TABLE `pedidos` (
  `num_pedido` int(11) NOT NULL,
  `id_cliente` int(11) NOT NULL,
  `id_endereco` int(11) NOT NULL,
  `id_pagto` int(11) NOT NULL,
  `total_prod` decimal(10,2) DEFAULT NULL,
  `total_frete` decimal(10,2) DEFAULT NULL,
  `total_desc` decimal(10,2) DEFAULT NULL,
  `total_pedido` decimal(10,2) DEFAULT NULL,
  `data_pedido` datetime NOT NULL,
  `previsao_entrega` date DEFAULT NULL,
  `efetiva_entrega` date DEFAULT NULL,
  `status_ped` enum('A','S','F','T','E') DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

--
-- Acionadores `pedidos`
--
DELIMITER $$
CREATE TRIGGER `pedidos_AFTER_INSERT` AFTER INSERT ON `pedidos` FOR EACH ROW BEGIN
	insert into rastreabilidade values (new.num_pedido, new.status_ped,now(),user());
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `pedidos_AFTER_UPDATE` AFTER UPDATE ON `pedidos` FOR EACH ROW BEGIN
	insert into rastreabilidade
	values(new.num_pedido,new.status_ped,now(),user());
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Estrutura da tabela `pedido_itens`
--

CREATE TABLE `pedido_itens` (
  `num_pedido` int(11) NOT NULL,
  `id_produto` int(11) NOT NULL,
  `qtd` int(11) NOT NULL,
  `val_unit` decimal(10,2) NOT NULL,
  `desconto` decimal(10,2) NOT NULL,
  `total` decimal(10,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- --------------------------------------------------------

--
-- Estrutura da tabela `pedido_obs`
--

CREATE TABLE `pedido_obs` (
  `num_pedido` int(11) NOT NULL,
  `obs` varchar(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- --------------------------------------------------------

--
-- Estrutura da tabela `produto`
--

CREATE TABLE `produto` (
  `id_produto` int(11) NOT NULL,
  `descricao` varchar(100) NOT NULL,
  `id_categoria` int(11) NOT NULL,
  `id_fabricante` int(11) NOT NULL,
  `preco_custo` decimal(10,2) DEFAULT NULL,
  `preco_venda` decimal(10,2) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

--
-- Extraindo dados da tabela `produto`
--

INSERT INTO `produto` (`id_produto`, `descricao`, `id_categoria`, `id_fabricante`, `preco_custo`, `preco_venda`) VALUES
(1, 'Jogo Infantil', 1, 1, '50.00', '200.00'),
(2, 'Jogo Acao', 1, 1, '50.00', '200.00'),
(3, 'Jogo Estrategia', 1, 1, '50.00', '200.00'),
(4, 'Smart Tv 42', 2, 2, '1300.00', '2000.00'),
(5, 'Notebook 15', 2, 2, '2200.00', '3000.00'),
(6, 'SmartPhone', 2, 2, '550.00', '1200.00'),
(7, 'Caixa de Som BOOM', 3, 3, '750.00', '1500.00'),
(8, 'Som automotivo', 3, 3, '250.00', '500.00'),
(9, 'Sound MIX', 3, 3, '750.00', '1200.00'),
(10, 'Geladeira', 4, 4, '780.00', '1580.00'),
(11, 'Batedeira', 4, 4, '200.00', '450.00'),
(12, 'Aspirador de Pó', 4, 4, '200.00', '4500.00'),
(13, 'Jogo Infantil', 1, 1, '50.00', '200.00'),
(14, 'Jogo Acao', 1, 1, '50.00', '200.00'),
(15, 'Jogo Estrategia', 1, 1, '50.00', '200.00'),
(16, 'Smart Tv 42', 2, 2, '1300.00', '2000.00'),
(17, 'Notebook 15', 2, 2, '2200.00', '3000.00'),
(18, 'SmartPhone', 2, 2, '550.00', '1200.00');

-- --------------------------------------------------------

--
-- Estrutura da tabela `produto_caracter`
--

CREATE TABLE `produto_caracter` (
  `id_produto` int(11) NOT NULL,
  `caracteristica` varchar(50) NOT NULL,
  `valor` varchar(50) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- --------------------------------------------------------

--
-- Estrutura da tabela `rastreabilidade`
--

CREATE TABLE `rastreabilidade` (
  `num_pedido` int(11) NOT NULL,
  `status_ped` char(1) NOT NULL,
  `data_hora` datetime NOT NULL,
  `id_user` varchar(50) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- --------------------------------------------------------

--
-- Estrutura da tabela `unidade_federal`
--

CREATE TABLE `unidade_federal` (
  `cod_uf` tinyint(4) NOT NULL,
  `uf` char(2) NOT NULL,
  `nome_uf` varchar(50) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

--
-- Extraindo dados da tabela `unidade_federal`
--

INSERT INTO `unidade_federal` (`cod_uf`, `uf`, `nome_uf`) VALUES
(0, '', '');

-- --------------------------------------------------------

--
-- Estrutura da tabela `usuarios`
--

CREATE TABLE `usuarios` (
  `id_user` int(11) NOT NULL,
  `nome_user` varchar(50) NOT NULL,
  `email_user` varchar(60) NOT NULL,
  `senha` varchar(32) NOT NULL,
  `data_cadastro` datetime NOT NULL,
  `status` enum('A','B') DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- --------------------------------------------------------

--
-- Estrutura stand-in para vista `v_financeiro`
-- (Veja abaixo para a view atual)
--
CREATE TABLE `v_financeiro` (
`num_nota` int(11)
,`id_cliente` int(11)
,`nome` varchar(32)
,`id_pagto` int(11)
,`descricao` varchar(50)
,`tipo` enum('C','D','B')
,`total_nf` decimal(10,2)
,`data_nf` datetime
,`parcela` int(11)
,`percentual` decimal(10,2)
,`dias` int(11)
,`valor_parcela` decimal(10,2)
,`vencimento` date
);

-- --------------------------------------------------------

--
-- Estrutura para vista `v_financeiro`
--
DROP TABLE IF EXISTS `v_financeiro`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_financeiro`  AS SELECT `a`.`num_nota` AS `num_nota`, `a`.`id_cliente` AS `id_cliente`, `d`.`nome` AS `nome`, `a`.`id_pagto` AS `id_pagto`, `b`.`descricao` AS `descricao`, `b`.`tipo` AS `tipo`, `a`.`total_nf` AS `total_nf`, `a`.`data_nf` AS `data_nf`, `c`.`parcela` AS `parcela`, `c`.`percentual` AS `percentual`, `c`.`dias` AS `dias`, cast(`a`.`total_nf` / 100 * `c`.`percentual` as decimal(10,2)) AS `valor_parcela`, cast(`a`.`data_nf` + interval `c`.`dias` day as date) AS `vencimento` FROM (((`nota_fiscal` `a` join `cond_pagto` `b` on(`a`.`id_pagto` = `b`.`id_pagto`)) join `cond_pagto_det` `c` on(`a`.`id_pagto` = `b`.`id_pagto` and `a`.`id_pagto` = `c`.`id_pagto`)) join `clientes` `d` on(`a`.`id_cliente` = `d`.`id_cliente`)) WHERE `a`.`status_nf` = 'N''N'  ;

--
-- Índices para tabelas despejadas
--

--
-- Índices para tabela `carrinho_compras`
--
ALTER TABLE `carrinho_compras`
  ADD KEY `id_produto` (`id_produto`),
  ADD KEY `ix_cc_1` (`sessao`);

--
-- Índices para tabela `categorias`
--
ALTER TABLE `categorias`
  ADD PRIMARY KEY (`id_categoria`);

--
-- Índices para tabela `cidades`
--
ALTER TABLE `cidades`
  ADD PRIMARY KEY (`id_cidade`),
  ADD KEY `fk_cid_1` (`cod_uf`);

--
-- Índices para tabela `clientes`
--
ALTER TABLE `clientes`
  ADD PRIMARY KEY (`id_cliente`);

--
-- Índices para tabela `cliente_endereco`
--
ALTER TABLE `cliente_endereco`
  ADD PRIMARY KEY (`id_endereco`),
  ADD KEY `id_cliente` (`id_cliente`),
  ADD KEY `id_cidade` (`id_cidade`);

--
-- Índices para tabela `cond_pagto`
--
ALTER TABLE `cond_pagto`
  ADD PRIMARY KEY (`id_pagto`);

--
-- Índices para tabela `cond_pagto_det`
--
ALTER TABLE `cond_pagto_det`
  ADD KEY `id_pagto` (`id_pagto`);

--
-- Índices para tabela `estoque`
--
ALTER TABLE `estoque`
  ADD KEY `id_produto` (`id_produto`);

--
-- Índices para tabela `fabricantes`
--
ALTER TABLE `fabricantes`
  ADD PRIMARY KEY (`id_fabricante`);

--
-- Índices para tabela `nf_itens`
--
ALTER TABLE `nf_itens`
  ADD KEY `num_nota` (`num_nota`),
  ADD KEY `id_produto` (`id_produto`);

--
-- Índices para tabela `nf_obs`
--
ALTER TABLE `nf_obs`
  ADD KEY `num_nota` (`num_nota`);

--
-- Índices para tabela `nota_fiscal`
--
ALTER TABLE `nota_fiscal`
  ADD PRIMARY KEY (`num_nota`),
  ADD KEY `num_ped_ref` (`num_ped_ref`),
  ADD KEY `id_cliente` (`id_cliente`),
  ADD KEY `id_endereco` (`id_endereco`),
  ADD KEY `id_pagto` (`id_pagto`);

--
-- Índices para tabela `pedidos`
--
ALTER TABLE `pedidos`
  ADD PRIMARY KEY (`num_pedido`),
  ADD KEY `id_cliente` (`id_cliente`),
  ADD KEY `id_endereco` (`id_endereco`),
  ADD KEY `id_pagto` (`id_pagto`);

--
-- Índices para tabela `pedido_itens`
--
ALTER TABLE `pedido_itens`
  ADD KEY `num_pedido` (`num_pedido`),
  ADD KEY `id_produto` (`id_produto`);

--
-- Índices para tabela `pedido_obs`
--
ALTER TABLE `pedido_obs`
  ADD KEY `num_pedido` (`num_pedido`);

--
-- Índices para tabela `produto`
--
ALTER TABLE `produto`
  ADD PRIMARY KEY (`id_produto`),
  ADD KEY `id_categoria` (`id_categoria`),
  ADD KEY `id_fabricante` (`id_fabricante`);

--
-- Índices para tabela `produto_caracter`
--
ALTER TABLE `produto_caracter`
  ADD KEY `id_produto` (`id_produto`);

--
-- Índices para tabela `rastreabilidade`
--
ALTER TABLE `rastreabilidade`
  ADD KEY `num_pedido` (`num_pedido`);

--
-- Índices para tabela `unidade_federal`
--
ALTER TABLE `unidade_federal`
  ADD PRIMARY KEY (`cod_uf`);

--
-- Índices para tabela `usuarios`
--
ALTER TABLE `usuarios`
  ADD PRIMARY KEY (`id_user`),
  ADD UNIQUE KEY `ix_usr_1` (`email_user`);

--
-- AUTO_INCREMENT de tabelas despejadas
--

--
-- AUTO_INCREMENT de tabela `categorias`
--
ALTER TABLE `categorias`
  MODIFY `id_categoria` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=13;

--
-- AUTO_INCREMENT de tabela `cidades`
--
ALTER TABLE `cidades`
  MODIFY `id_cidade` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT de tabela `clientes`
--
ALTER TABLE `clientes`
  MODIFY `id_cliente` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de tabela `cliente_endereco`
--
ALTER TABLE `cliente_endereco`
  MODIFY `id_endereco` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=103;

--
-- AUTO_INCREMENT de tabela `cond_pagto`
--
ALTER TABLE `cond_pagto`
  MODIFY `id_pagto` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT de tabela `fabricantes`
--
ALTER TABLE `fabricantes`
  MODIFY `id_fabricante` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=17;

--
-- AUTO_INCREMENT de tabela `nota_fiscal`
--
ALTER TABLE `nota_fiscal`
  MODIFY `num_nota` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de tabela `pedidos`
--
ALTER TABLE `pedidos`
  MODIFY `num_pedido` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT de tabela `produto`
--
ALTER TABLE `produto`
  MODIFY `id_produto` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=19;

--
-- AUTO_INCREMENT de tabela `usuarios`
--
ALTER TABLE `usuarios`
  MODIFY `id_user` int(11) NOT NULL AUTO_INCREMENT;

--
-- Restrições para despejos de tabelas
--

--
-- Limitadores para a tabela `carrinho_compras`
--
ALTER TABLE `carrinho_compras`
  ADD CONSTRAINT `carrinho_compras_ibfk_1` FOREIGN KEY (`id_produto`) REFERENCES `produto` (`id_produto`);

--
-- Limitadores para a tabela `cidades`
--
ALTER TABLE `cidades`
  ADD CONSTRAINT `fk_cid_1` FOREIGN KEY (`cod_uf`) REFERENCES `unidade_federal` (`cod_uf`);

--
-- Limitadores para a tabela `cliente_endereco`
--
ALTER TABLE `cliente_endereco`
  ADD CONSTRAINT `cliente_endereco_ibfk_1` FOREIGN KEY (`id_cliente`) REFERENCES `clientes` (`id_cliente`),
  ADD CONSTRAINT `cliente_endereco_ibfk_2` FOREIGN KEY (`id_cidade`) REFERENCES `cidades` (`id_cidade`);

--
-- Limitadores para a tabela `cond_pagto_det`
--
ALTER TABLE `cond_pagto_det`
  ADD CONSTRAINT `cond_pagto_det_ibfk_1` FOREIGN KEY (`id_pagto`) REFERENCES `cond_pagto` (`id_pagto`);

--
-- Limitadores para a tabela `estoque`
--
ALTER TABLE `estoque`
  ADD CONSTRAINT `estoque_ibfk_1` FOREIGN KEY (`id_produto`) REFERENCES `produto` (`id_produto`);

--
-- Limitadores para a tabela `nf_itens`
--
ALTER TABLE `nf_itens`
  ADD CONSTRAINT `nf_itens_ibfk_1` FOREIGN KEY (`num_nota`) REFERENCES `nota_fiscal` (`num_nota`),
  ADD CONSTRAINT `nf_itens_ibfk_2` FOREIGN KEY (`id_produto`) REFERENCES `produto` (`id_produto`);

--
-- Limitadores para a tabela `nf_obs`
--
ALTER TABLE `nf_obs`
  ADD CONSTRAINT `nf_obs_ibfk_1` FOREIGN KEY (`num_nota`) REFERENCES `nota_fiscal` (`num_nota`);

--
-- Limitadores para a tabela `nota_fiscal`
--
ALTER TABLE `nota_fiscal`
  ADD CONSTRAINT `nota_fiscal_ibfk_1` FOREIGN KEY (`num_ped_ref`) REFERENCES `pedidos` (`num_pedido`),
  ADD CONSTRAINT `nota_fiscal_ibfk_2` FOREIGN KEY (`id_cliente`) REFERENCES `clientes` (`id_cliente`),
  ADD CONSTRAINT `nota_fiscal_ibfk_3` FOREIGN KEY (`id_endereco`) REFERENCES `cliente_endereco` (`id_endereco`),
  ADD CONSTRAINT `nota_fiscal_ibfk_4` FOREIGN KEY (`id_pagto`) REFERENCES `cond_pagto_det` (`id_pagto`);

--
-- Limitadores para a tabela `pedidos`
--
ALTER TABLE `pedidos`
  ADD CONSTRAINT `pedidos_ibfk_1` FOREIGN KEY (`id_cliente`) REFERENCES `clientes` (`id_cliente`),
  ADD CONSTRAINT `pedidos_ibfk_2` FOREIGN KEY (`id_endereco`) REFERENCES `cliente_endereco` (`id_endereco`),
  ADD CONSTRAINT `pedidos_ibfk_3` FOREIGN KEY (`id_pagto`) REFERENCES `cond_pagto` (`id_pagto`);

--
-- Limitadores para a tabela `pedido_itens`
--
ALTER TABLE `pedido_itens`
  ADD CONSTRAINT `pedido_itens_ibfk_1` FOREIGN KEY (`num_pedido`) REFERENCES `pedidos` (`num_pedido`),
  ADD CONSTRAINT `pedido_itens_ibfk_2` FOREIGN KEY (`id_produto`) REFERENCES `produto` (`id_produto`);

--
-- Limitadores para a tabela `pedido_obs`
--
ALTER TABLE `pedido_obs`
  ADD CONSTRAINT `pedido_obs_ibfk_1` FOREIGN KEY (`num_pedido`) REFERENCES `pedidos` (`num_pedido`);

--
-- Limitadores para a tabela `produto`
--
ALTER TABLE `produto`
  ADD CONSTRAINT `produto_ibfk_1` FOREIGN KEY (`id_categoria`) REFERENCES `categorias` (`id_categoria`),
  ADD CONSTRAINT `produto_ibfk_2` FOREIGN KEY (`id_fabricante`) REFERENCES `fabricantes` (`id_fabricante`);

--
-- Limitadores para a tabela `produto_caracter`
--
ALTER TABLE `produto_caracter`
  ADD CONSTRAINT `produto_caracter_ibfk_1` FOREIGN KEY (`id_produto`) REFERENCES `produto` (`id_produto`);

--
-- Limitadores para a tabela `rastreabilidade`
--
ALTER TABLE `rastreabilidade`
  ADD CONSTRAINT `rastreabilidade_ibfk_1` FOREIGN KEY (`num_pedido`) REFERENCES `pedidos` (`num_pedido`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
