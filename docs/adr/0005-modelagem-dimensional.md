# ADR-005: Modelagem Dimensional para Contratos Imobiliários

**Status:** Aceito
**Data:** 2026-04-09
**Autores:** Lucas de Araújo (@lucasricardoaa)
**Ferramentas:** Documentação estruturada com Claude (Anthropic)
**Tags:** modelagem, dimensional, fatos, dimensões, bigquery, dbt, marts

---

## Contexto

O projeto transforma dados de parcelas de contratos imobiliários em modelos
analíticos prontos para consumo. Os dados originam-se de duas abas mensais
(`payments` e `receivables`) que, após anonimização e ingestão, chegam ao
dbt como `raw.raw_payments` e `raw.raw_receivables`.

A análise dos dados revela:

- **Granularidade natural:** `contract_code` + `installment_id` é chave
  única em ambas as abas — cada linha representa uma parcela específica
  de um contrato
- **Titulares com múltiplos contratos:** um mesmo titular pode possuir
  vários contratos e unidades distintas — `dim_titular` e `dim_unit`
  são dimensões independentes
- **CNPJ confirmado:** titulares podem ser pessoas jurídicas
  (`17.764.495/0001-28` possui 4 contratos no dataset)
- **Status de parcela:** o campo `payment_status` discrimina parcelas
  pagas (`paid`) de não pagas (`pending`), derivado da aba de origem
- **Snapshot mensal:** cada arquivo representa o estado das parcelas
  em um mês de referência (`date_reference`), não um registro histórico
  de eventos

É necessário decidir a estrutura dimensional da camada de marts:
granularidade da tabela de fatos, quais dimensões existem, como tratar
titulares com múltiplos contratos, e qual estratégia de chave surrogate
adotar.

---

## Decisão

Adotamos **modelagem dimensional clássica** com uma tabela de fatos
no nível de parcela e quatro dimensões: titular, contrato, unidade e data.

### Modelo dimensional

```
dim_titular ──┐
              │
dim_contract ─┼──► fct_installments ◄── dim_date
              │
dim_unit ─────┘
```

---

### Tabela de fatos: `fct_installments`

**Granularidade:** uma linha por parcela por mês de referência.
A chave natural é `contract_code` + `installment_id` + `date_reference`.

**Chave surrogate:**
```sql
{{ dbt_utils.generate_surrogate_key([
    'contract_code', 'installment_id', 'date_reference'
]) }} AS installment_sk
```

| Coluna | Tipo | Descrição |
|---|---|---|
| `installment_sk` | STRING | Chave surrogate da parcela (PK) |
| `contract_sk` | STRING | FK → dim_contract |
| `unit_sk` | STRING | FK → dim_unit |
| `titular_sk` | STRING | FK → dim_titular |
| `date_reference_sk` | STRING | FK → dim_date (mês de referência) |
| `date_maturity_sk` | STRING | FK → dim_date (vencimento) |
| `date_payment_sk` | STRING | FK → dim_date (pagamento — NULL se pendente) |
| `date_reference` | DATE | Mês de referência do arquivo |
| `date_upload` | DATETIME | Timestamp do carregamento |
| `payment_status` | STRING | `'paid'` ou `'pending'` |
| `installment_id` | INT64 | Número sequencial da parcela no contrato |
| `installment_type` | STRING | Tipo da parcela (ex: Parcelas Mensais) |
| `date_maturity` | DATE | Data de vencimento |
| `date_payment` | DATE | Data de pagamento (NULL se pendente) |
| `original_value` | NUMERIC | Valor original da parcela |
| `present_value` | NUMERIC | Valor presente |
| `value_with_addiction` | NUMERIC | Valor com acréscimos |
| `value_payment` | NUMERIC | Valor efetivamente pago (NULL se pendente) |
| `value_original` | NUMERIC | Valor original do imóvel |
| `interest_rate` | NUMERIC | Taxa de juros aplicada |
| `index` | STRING | Índice de correção (ex: INCC) |
| `financing_type` | STRING | Tipo de financiamento |
| `condition_id` | STRING | ID da condição de pagamento |

---

### Dimensão: `dim_titular`

Representa o titular do contrato — pessoa física (CPF) ou jurídica (CNPJ),
ambos anonimizados. Um titular pode possuir múltiplos contratos.

**Chave surrogate:**
```sql
{{ dbt_utils.generate_surrogate_key(['titular_code']) }} AS titular_sk
```

| Coluna | Tipo | Descrição |
|---|---|---|
| `titular_sk` | STRING | Chave surrogate (PK) |
| `titular_code` | STRING | Hash do CPF ou CNPJ (anonimizado) |
| `titular_name` | STRING | Nome fictício gerado pelo Faker |
| `titular_type` | STRING | `'PF'` ou `'PJ'` — derivado do formato do código original |

**Nota:** `titular_type` é derivado pelo script de anonimização com base
no formato do documento original antes do hash — CPF (`NNN.NNN.NNN-NN`)
→ `'PF'`; CNPJ (`NN.NNN.NNN/NNNN-NN`) → `'PJ'`. Esse campo é preservado
pois não permite reidentificação mas agrega valor analítico.

**Estratégia SCD:** Type 1 — sobrescrita simples. Para um portfólio,
não há necessidade de rastrear mudanças históricas de titular.

---

### Dimensão: `dim_contract`

Representa o contrato imobiliário. Um contrato pertence a um titular
e a uma unidade, mas titular e unidade são dimensões independentes
para suportar o caso de múltiplos contratos por titular.

**Chave surrogate:**
```sql
{{ dbt_utils.generate_surrogate_key(['contract_code']) }} AS contract_sk
```

| Coluna | Tipo | Descrição |
|---|---|---|
| `contract_sk` | STRING | Chave surrogate (PK) |
| `contract_code` | STRING | Hash do código do contrato (anonimizado) |
| `titular_sk` | STRING | FK → dim_titular |
| `unit_sk` | STRING | FK → dim_unit |
| `emission_date` | DATE | Data de emissão do contrato |
| `base_date` | DATE | Data base do contrato |
| `financing_type` | STRING | Tipo de financiamento |
| `value_original` | NUMERIC | Valor original do imóvel no contrato |

**Estratégia SCD:** Type 1 — sobrescrita simples.

---

### Dimensão: `dim_unit`

Representa a unidade imobiliária. Uma unidade pode estar associada
a múltiplos contratos ao longo do tempo (ex: revenda), mas no dataset
atual cada `unit_id` aparece com um único contrato.

**Chave surrogate:**
```sql
{{ dbt_utils.generate_surrogate_key(['unit_id']) }} AS unit_sk
```

| Coluna | Tipo | Descrição |
|---|---|---|
| `unit_sk` | STRING | Chave surrogate (PK) |
| `unit_id` | INT64 | ID da unidade |
| `unit_name` | STRING | Nome/número da unidade |
| `estate_code` | INT64 | Código fictício do empreendimento |
| `estate_name` | STRING | Nome fictício do empreendimento |
| `estate_address` | STRING | Endereço fictício do empreendimento |
| `estate_schedule_code` | STRING | Código de bloco/fase |
| `estate_typology_code` | STRING | Código da tipologia |
| `property_type` | STRING | Tipo do imóvel (ex: APARTAMENTO) |
| `floor` | STRING | Andar |
| `private_area` | NUMERIC | Área privativa (m²) |
| `common_area` | NUMERIC | Área comum (m²) |
| `usable_area` | NUMERIC | Área útil (m²) |
| `terrain_area` | NUMERIC | Área de terreno (m²) |

**Estratégia SCD:** Type 1 — sobrescrita simples.

---

### Dimensão: `dim_date`

Dimensão de datas gerada via `dbt_utils.date_spine`, cobrindo o intervalo
completo de datas relevantes ao projeto. Usada para três papéis distintos
em `fct_installments`: mês de referência, vencimento e pagamento.

**Intervalo:** do menor `date_reference` ao maior `date_maturity`
presente nos dados, com margem de 1 ano para cada lado.

**Chave surrogate:**
```sql
{{ dbt_utils.generate_surrogate_key(['date_day']) }} AS date_sk
```

| Coluna | Tipo | Descrição |
|---|---|---|
| `date_sk` | STRING | Chave surrogate (PK) |
| `date_day` | DATE | Data completa |
| `year` | INT64 | Ano |
| `quarter` | INT64 | Trimestre (1–4) |
| `month` | INT64 | Mês (1–12) |
| `month_name` | STRING | Nome do mês em português |
| `week_of_year` | INT64 | Semana do ano |
| `day_of_week` | INT64 | Dia da semana (1=Segunda, 7=Domingo) |
| `day_name` | STRING | Nome do dia em português |
| `is_weekend` | BOOLEAN | TRUE se sábado ou domingo |
| `year_month` | STRING | Formato `YYYY-MM` para agrupamentos mensais |

---

## Motivação

- **Granularidade no nível de parcela:** é o nível mais atômico
  disponível nos dados e permite todas as agregações relevantes:
  por contrato, por titular, por unidade, por mês, por status
- **`dim_titular` separada de `dim_contract`:** um titular com múltiplos
  contratos (padrão confirmado nos dados) seria duplicado em
  `dim_contract` se os atributos do titular ficassem nela — a separação
  normaliza corretamente e evita inconsistências
- **Chaves surrogate em todos os modelos:** garante estabilidade das
  FKs mesmo se os identificadores naturais forem alterados; segue
  boas práticas de modelagem dimensional e demonstra conhecimento
  de `dbt_utils`
- **`titular_type` derivado antes do hash:** a distinção PF/PJ é
  analiticamente relevante e não permite reidentificação — preservá-la
  enriquece o modelo sem violar a anonimização do ADR-003
- **SCD Type 1 em todas as dimensões:** adequado para portfólio;
  não há requisito de rastreamento histórico de atributos dimensionais
- **`dim_date` via `date_spine`:** abordagem idiomática do ecossistema
  dbt; suporta múltiplos papéis de data em `fct_installments` sem
  duplicação de lógica

---

## Alternativas consideradas

| Alternativa | Por que foi descartada |
|---|---|
| One Big Table (OBT) | Mais simples, mas não demonstra conhecimento de modelagem dimensional — objetivo central deste portfólio |
| Titular dentro de `dim_contract` | Causaria duplicação de atributos do titular para contratos múltiplos do mesmo titular — confirmado como padrão real nos dados |
| Granularidade no nível de contrato (agregada) | Perderia a riqueza analítica das parcelas individuais — vencimento, valor pago vs. devido, inadimplência por parcela |
| SCD Type 2 para dimensões | Válido para produção com histórico de mudanças; excessivo para um portfólio sem requisito de rastreamento histórico |
| Chaves naturais em vez de surrogate | Chaves naturais estão anonimizadas (hashes) — surrogates são mais estáveis e seguem boas práticas dimensionais |

---

## Consequências

### Positivas

- Modelo analiticamente rico: permite análises de inadimplência,
  evolução de valores, perfil de titulares (PF vs PJ), distribuição
  por tipologia de imóvel e sazonalidade
- Estrutura reconhecível por qualquer analista ou engenheiro de dados
  familiarizado com modelagem dimensional
- Chaves surrogate garantem integridade referencial estável
- `dim_date` suporta análises temporais sofisticadas sem lógica
  de data espalhada pelos modelos de fatos

### Negativas / Trade-offs

- **Quatro dimensões para um dataset pequeno:** pode parecer excessivo
  para 629 KB — mas é o objetivo de demonstração técnica do portfólio
- **`titular_type` depende do script de anonimização:** se o campo
  não for gerado corretamente no ADR-003, a dimensão perde uma
  informação analítica importante — documentado como dependência crítica
- **SCD Type 1 perde histórico:** se atributos de um contrato ou
  unidade mudarem entre arquivos mensais, a versão anterior é
  sobrescrita — aceitável para este portfólio

---

## Decisões relacionadas

- **Depende de:** ADR-003 (Anonimização) — `titular_type` deve ser
  gerado pelo script de anonimização antes do hash de `titular_code`;
  os campos `estate_*` fictícios são usados diretamente em `dim_unit`
- **Depende de:** ADR-004 (Camadas dbt) — os modelos de marts seguem
  as convenções de prefixo, materialização e referência definidas
  no ADR-004
- **Influencia:** ADR-006 (Testes e qualidade) — as chaves surrogate
  e FKs definidas aqui são os principais alvos de testes de
  integridade referencial

---

## Notas para agentes Claude CLI

- A granularidade de `fct_installments` é parcela por mês de
  referência — nunca agregue na tabela de fatos
- A chave surrogate de `fct_installments` é composta por
  `contract_code` + `installment_id` + `date_reference`
- `dim_titular` é separada de `dim_contract` — nunca mova atributos
  do titular para dentro de `dim_contract`
- O campo `titular_type` (`'PF'` ou `'PJ'`) vem do script de
  anonimização — nunca tente derivá-lo a partir do `titular_code`
  hashado nos modelos dbt
- Todas as dimensões usam SCD Type 1 — nunca implemente Type 2
  sem instrução explícita do usuário
- `dim_date` é gerada via `dbt_utils.date_spine` — nunca use seed
  CSV para a dimensão de datas
- `fct_installments` tem três FKs para `dim_date`: `date_reference_sk`,
  `date_maturity_sk` e `date_payment_sk` — ao gerar joins analíticos,
  sempre especifique qual papel de data está sendo usado
- `date_payment_sk` é NULL para registros com `payment_status = 'pending'`
  — trate como nullable em testes e joins
- Ao gerar testes de integridade referencial, verifique todas as FKs
  de `fct_installments` contra suas respectivas dimensões
- Nunca exponha campos anonimizados (`titular_code`, `contract_code`)
  como chaves de negócio visíveis — use sempre as chaves surrogate
  para joins e as colunas de display (ex: `titular_name`) para
  apresentação
