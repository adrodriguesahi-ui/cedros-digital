-- Correção dos textos dos requisitos das classes (uma vez só).
--
-- O QUE ACONTECEU
-- O catálogo de textos do app tinha o enunciado colado no requisito errado e
-- guardava o nome da SEÇÃO da ficha ("I. GERAIS", "CLASSE AVANÇADA – …") como
-- título do requisito. O catálogo já foi corrigido no app.
--
-- Só que o modo "Ordenar" gravava, junto com a posição de cada requisito, uma
-- CÓPIA do texto que estava valendo na hora. Essa cópia ficou no banco e vence
-- o catálogo — então, sem limpar, a correção não chega na tela.
--
-- O app agora trata campo em branco como "usa o catálogo", então basta apagar
-- a cópia. Posição, descrição, observação e os requisitos criados à mão não
-- são tocados.
--
-- Rode DEPOIS de publicar a versão nova do app.

-- 1) Olhar antes: quantas linhas carregam a cópia, por classe.
select classe, count(*) as linhas_com_copia
from requisitos_personalizados
where coalesce(criado, false) = false
  and titulo is not null
  and (titulo ~ '^[IVX]+\.' or titulo like 'CLASSE AVAN%' or titulo ~ '^\d+\.')
group by classe
order by classe;

-- 2) Apagar só a cópia. O que o coordenador escreveu de propósito não entra
--    aqui: um título reescrito à mão não se parece com nome de seção.
update requisitos_personalizados
set titulo = null,
    subtitulo = null,
    area = null,
    subitens_modo = null
where coalesce(criado, false) = false
  and titulo is not null
  and (titulo ~ '^[IVX]+\.' or titulo like 'CLASSE AVAN%' or titulo ~ '^\d+\.');

-- 3) Conferir: tem que voltar zero linha.
select count(*) as ainda_com_copia
from requisitos_personalizados
where coalesce(criado, false) = false
  and titulo is not null
  and (titulo ~ '^[IVX]+\.' or titulo like 'CLASSE AVAN%' or titulo ~ '^\d+\.');
