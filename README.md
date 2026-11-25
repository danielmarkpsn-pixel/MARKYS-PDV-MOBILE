# MARKYS PDV MOBILE

Aplicativo de ponto de venda **independente do MARKYS PDV para PC**, com identidade em azul marinho claro e navegação inspirada no vídeo de referência fornecido pelo proprietário.

## Estado atual (fase 1)

- Base Flutter/Dart e tema visual (#52749D azul principal; #303946 menu lateral).
- Banco SQLite armazenado no aparelho: empresas, produtos, clientes, vendas e itens.
- Cadastro local da empresa.
- Tela inicial, resumo zerado e menu lateral com todos os módulos planejados.
- As demais áreas ainda apresentam mensagens de desenvolvimento; não são operações funcionais.
- **Login Google e e-mail/senha ainda não implementados**. Deve ser integrado a um provedor de autenticação, sem colocar senhas em texto simples no SQLite.
- **Sem APK gerado ainda.** A estrutura Android precisa ser gerada com o SDK Flutter.

## Preparar o projeto

1. Instalar o Flutter SDK e Android SDK.
2. Clonar o repositório e mudar para a branch de desenvolvimento.
3. Executar `flutter create --platforms=android --org com.markys .` para gerar os arquivos Android.
4. Executar `flutter pub get` e `flutter run`.
5. Para o APK, após configuração e testes: `flutter build apk --release`.

Não comitar credenciais, chaves de assinatura, nem `google-services.json`.

## Próximas etapas

1. Autenticação Google e e-mail/senha e recuperação de conta; configurar Firebase por projeto.
2. CRUD de produtos, imagens, estoque e clientes localmente.
3. PDV com grade de três colunas, carrinho, pagamento, recibo e transação SQLite atômica.
4. Pedidos, histórico, finanças, estatísticas, controle de fiado e backup.
5. Câmera e impressão Bluetooth.

**Importante:** os dados comerciais são locais. Desinstalação, perda do aparelho ou limpeza dos dados podem destruí-los; implementar exportação/backup e restauração antes de uso real.
