# Painel administrativo — como ativar (Victor & Paula)

O site funciona hoje em **modo local** (sem banco). Para ativar o banco de dados
real, o painel `/admin` e a sincronização, siga estes passos uma única vez:

## 1. Criar o projeto Supabase (grátis)

1. Acesse [supabase.com](https://supabase.com) e crie uma conta;
2. Crie um projeto (região `Northeast Asia (Tokyo)` é a mais próxima);
3. Guarde a **URL do projeto** e a **anon key** (Settings → API).
   A anon key é pública por design — quem protege os dados são as políticas
   RLS criadas pelo script abaixo.

## 2. Criar as tabelas

1. No painel do Supabase, abra **SQL Editor**;
2. Cole todo o conteúdo de `supabase/schema.sql` e execute;
3. **Importante:** edite os dois e-mails no bloco `admin_users` (topo do
   arquivo) para os e-mails reais de Victor e Paula antes de rodar — ou rode
   depois: `update admin_users set email = 'email@real.com' where display_name = 'Victor';`

## 3. Criar os usuários de Victor e Paula

1. No Supabase: **Authentication → Users → Add user**;
2. Crie um usuário para cada um, com os mesmos e-mails cadastrados em
   `admin_users`, e defina as senhas ali (nenhuma senha fica no código);
3. Só esses dois e-mails conseguem ler os dados — qualquer outra conta é
   bloqueada pelas políticas RLS.

## 4. Colar as credenciais no site

Nos dois arquivos, preencha as duas constantes no topo do `<script>`:

- `index.html` → `SUPABASE_URL` e `SUPABASE_ANON_KEY`
- `admin.html` → `SUPABASE_URL` e `SUPABASE_ANON_KEY`

Publique o site (Netlify etc.). Pronto:

- O convite passa a registrar confirmações, fraldas, presentes (com
  exclusividade real) e mensagens no banco;
- Cada convidado recebe um código de 4 dígitos para consultar/alterar suas
  escolhas em "Minhas escolhas";
- O painel fica em `https://SEU-SITE/admin.html` (sem link público).

## Enquanto não configurar

- O convite continua funcionando como hoje (modo local);
- O painel pode ser visto em `admin.html?demo=1` (dados fictícios, rotulado).

## Observações de segurança

- Row Level Security ativada em todas as tabelas;
- Convidados (anon) só leem: catálogo ativo, status dos presentes (sem nomes)
  e a prioridade de fraldas;
- Reserva de presente é atômica no servidor (índice único) — impossível dois
  convidados reservarem o mesmo item;
- Alterações do convidado exigem telefone + código;
- Telefones e nomes nunca aparecem publicamente.
