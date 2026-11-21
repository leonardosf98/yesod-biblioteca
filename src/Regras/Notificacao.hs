{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedStrings #-}
module Regras.Notificacao
    ( Aviso (..)
    , notificarSocio
    , notificarBibliotecarios
    , avisoPedidoNovo
    , avisoPedidoExpirado
    , avisoPedidoCancelado
    , avisoPedidoExpirando
    , avisoChegouSuaVez
    , avisoEmprestimoAtrasado
    , avisoDevolucaoAmanha
    ) where

import ClassyPrelude.Yesod
import Model
import Model.Tipos
import Regras.Comum (chaveDe, dataCurta, formatarCentavos)

data Aviso = Aviso
    { avisoTipo :: Text
    , avisoChave :: Text
    , avisoTitulo :: Text
    , avisoTexto :: Text
    , avisoLink :: Maybe Text
    }

-- A chave é única por usuário: a rotina pode rodar de novo sem duplicar o aviso.
novoAviso :: Text -> [Text] -> Text -> Text -> Text -> Aviso
novoAviso tipo referencia titulo texto destino = Aviso
    { avisoTipo = tipo
    , avisoChave = intercalate ":" (tipo : referencia)
    , avisoTitulo = titulo
    , avisoTexto = texto
    , avisoLink = Just destino
    }

notificarUsuario :: MonadIO m => Aviso -> UserId -> ReaderT SqlBackend m ()
notificarUsuario aviso userId = do
    agora <- liftIO getCurrentTime
    void $ insertUnique Notificacao
        { notificacaoUserId = userId
        , notificacaoTipo = avisoTipo aviso
        , notificacaoChave = avisoChave aviso
        , notificacaoTitulo = avisoTitulo aviso
        , notificacaoTexto = avisoTexto aviso
        , notificacaoLink = avisoLink aviso
        , notificacaoCriadaEm = agora
        , notificacaoLidaEm = Nothing
        }

notificarSocio :: MonadIO m => SocioId -> Aviso -> ReaderT SqlBackend m ()
notificarSocio socioId aviso =
    selectKeysList [UserSocioId ==. Just socioId] [] >>= mapM_ (notificarUsuario aviso)

notificarBibliotecarios :: MonadIO m => Aviso -> ReaderT SqlBackend m ()
notificarBibliotecarios aviso =
    selectKeysList [UserPapel ==. PapelBibliotecario] [] >>= mapM_ (notificarUsuario aviso)

doPedido :: PedidoId -> [Text]
doPedido pedidoId = ["pedido", chaveDe pedidoId]

doEmprestimo :: EmprestimoId -> Day -> [Text]
doEmprestimo emprestimoId dia = ["emprestimo", chaveDe emprestimoId, tshow dia]

linkDoLivro :: LivroId -> Text
linkDoLivro livroId = "/livros/" <> chaveDe livroId

avisoPedidoNovo :: Entity Pedido -> Text -> Text -> Text -> Aviso
avisoPedidoNovo (Entity pedidoId pedido) nomeDoSocio titulo codigoDoExemplar =
    novoAviso "pedido_novo" (doPedido pedidoId)
        ("Novo pedido: " <> titulo)
        (nomeDoSocio <> " pediu " <> titulo <> ". Separe o exemplar " <> codigoDoExemplar
            <> " (pedido " <> pedidoCodigo pedido <> ").")
        "/painel/pedidos"

avisoPedidoExpirado :: Entity Pedido -> LivroId -> Text -> Aviso
avisoPedidoExpirado (Entity pedidoId pedido) livroId titulo =
    novoAviso "pedido_expirado" (doPedido pedidoId)
        ("Pedido expirado: " <> titulo)
        ("O prazo para retirar o pedido " <> pedidoCodigo pedido <> " acabou e o exemplar voltou para a estante.")
        (linkDoLivro livroId)

avisoPedidoCancelado :: Entity Pedido -> LivroId -> Text -> Aviso
avisoPedidoCancelado (Entity pedidoId pedido) livroId titulo =
    novoAviso "pedido_cancelado" (doPedido pedidoId)
        ("Pedido cancelado: " <> titulo)
        ("A biblioteca cancelou o pedido " <> pedidoCodigo pedido <> ". Se ainda quiser o livro, faça um novo pedido.")
        (linkDoLivro livroId)

avisoPedidoExpirando :: Entity Pedido -> Text -> Text -> Aviso
avisoPedidoExpirando (Entity pedidoId pedido) titulo limite =
    novoAviso "pedido_expirando" (doPedido pedidoId)
        ("Retire até " <> limite <> ": " <> titulo)
        ("O pedido " <> pedidoCodigo pedido <> " expira em menos de 6 horas. Depois disso o exemplar volta para a estante.")
        "/emprestimos"

avisoChegouSuaVez :: Entity Pedido -> Text -> Text -> Text -> Aviso
avisoChegouSuaVez (Entity pedidoId pedido) titulo codigoDoExemplar limite =
    novoAviso "fila_disponivel" (doPedido pedidoId)
        ("Chegou a sua vez: " <> titulo)
        ("O exemplar " <> codigoDoExemplar <> " está separado para você até " <> limite
            <> ". Código do pedido: " <> pedidoCodigo pedido <> ".")
        "/emprestimos"

avisoEmprestimoAtrasado :: Entity Emprestimo -> Day -> Text -> Int -> Aviso
avisoEmprestimoAtrasado (Entity emprestimoId emprestimo) dia titulo multa =
    novoAviso "emprestimo_atrasado" (doEmprestimo emprestimoId dia)
        ("Devolução atrasada: " <> titulo)
        ("O prazo venceu em " <> dataCurta (emprestimoDataPrevista emprestimo) <> ". Multa prevista até hoje: "
            <> formatarCentavos multa <> ". Devolva no balcão.")
        "/emprestimos"

avisoDevolucaoAmanha :: Entity Emprestimo -> Text -> Aviso
avisoDevolucaoAmanha (Entity emprestimoId emprestimo) titulo =
    novoAviso "devolucao_vencendo" (doEmprestimo emprestimoId prevista)
        ("Devolva amanhã: " <> titulo)
        ("O prazo de devolução vence amanhã, " <> dataCurta prevista <> ". Se não houver fila, dá para renovar uma vez.")
        "/emprestimos"
  where
    prevista = emprestimoDataPrevista emprestimo
