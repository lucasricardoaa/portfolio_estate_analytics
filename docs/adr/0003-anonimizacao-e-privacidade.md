# ADR-003: Anonimização e Privacidade dos Dados

**Status:** Aceito  
**Data:** 2026-04-09  
**Autores:** Lucas de Araújo (@lucasricardoaa)
**Ferramentas:** Documentação estruturada com Claude (Anthropic)  
**Tags:** privacidade, anonimização, lgpd, pii, segurança, portfólio

---

## Contexto

O projeto utiliza dados reais de contratos imobiliários de uma incorporadora.
Os arquivos XLSX contêm dois tipos de informações protegidas:

**Dados PII (LGPD)** — informações de pessoas físicas identificáveis:
- `titular_name`: nome completo do titular do contrato
- `titular_code`: CPF ou CNPJ do titular (`NNN.NNN.NNN-NN` para PF,
  `NN.NNN.NNN/NNNN-NN` para PJ)

**Dados comercialmente sensíveis** — informações da incorporadora sujeitas
a acordo de confidencialidade:
- `estate_code`: código numérico do empreendimento
- `estate_name`: nome comercial do empreendimento
- `estate_address`: endereço completo do empreendimento

O repositório GitHub é público. Nenhum dado das categorias acima pode
aparecer em nenhum arquivo versionado, em nenhuma forma — nem diretamente,
nem em logs, nem em artefatos de teste.

A anonimização é executada pelo script `scripts/anonymize_and_load.py`,
que opera sobre os arquivos originais em `/data/original/`, anonimiza
em memória e carrega diretamente no BigQuery — sem persistência
intermediária em disco. Uma cópia Parquet é salva em `/data/processed/`
para auditoria local. Os originais nunca entram no repositório (ADR-001).

O arquivo analisado contém um único empreendimento, mas os demais arquivos
mensais podem conter empreendimentos distintos. A técnica de anonimização
deve tratar cada combinação única de `estate_code` + `estate_name` +
`estate_address` de forma consistente entre todos os arquivos — o mesmo
empreendimento real deve sempre produzir o mesmo empreendimento fictício.

---

## Decisão

Adotamos técnicas distintas por categoria e por finalidade de cada campo,
priorizando irreversibilidade para PII e substituição fictícia consistente
para dados comerciais sensíveis.

### Taxonomia e técnica por campo

| Campo | Categoria | Técnica | Resultado esperado |
|---|---|---|---|
| `titular_name` | PII | Substituição por nome fictício via Faker com seed fixo | `"João Silva"` → `"Carlos Mendes"` |
| `titular_code` | PII | Detecção automática de CPF ou CNPJ + SHA-256 com salt fixo, truncado em 12 chars | `"109.055.452-49"` → `"a3f9c2b1d84e"` |
| `titular_type` | Metadado derivado | Classificação `'PF'` ou `'PJ'` extraída do formato original **antes** do hash | `"109.055.452-49"` → `"PF"` |
| `contract_code` | Operacional sensível | SHA-256 com salt fixo, truncado em 8 chars | `"107"` → `"f3a1c9b2"` |
| `estate_code` | Comercial sensível | Mapeamento determinístico: inteiro sequencial fictício por valor único | `4` → `1` |
| `estate_name` | Comercial sensível | Mapeamento determinístico: nome fictício por valor único | `"Extension Berrini"` → `"Residencial Aurora"` |
| `estate_address` | Comercial sensível | Mapeamento determinístico: endereço fictício por valor único | endereço real → endereço inventado |

### Justificativa por técnica

**`titular_name` → Faker (nome fictício)**
Hash de nome produziria uma string sem sentido que prejudica a legibilidade
dos dados de portfólio. Nomes fictícios mantêm o dado semanticamente válido
para análise, sem qualquer ligação com pessoas reais. A biblioteca Faker
com seed fixo garante que o mesmo nome original sempre produza o mesmo nome
fictício — preservando consistência entre os 12 arquivos mensais.

**`titular_code` → detecção de tipo + SHA-256 com salt + truncagem**
O campo pode conter CPF (`NNN.NNN.NNN-NN`) ou CNPJ (`NN.NNN.NNN/NNNN-NN`).
O script de anonimização detecta o tipo pelo formato antes de aplicar o hash,
garantindo tratamento correto para ambos. O hash com salt impede rainbow table
attacks. O resultado truncado em 12 caracteres é suficiente para unicidade no
volume deste projeto e preserva a capacidade de fazer joins entre `payments`
e `receivables` pelo código do titular — sem revelar o documento real.
O salt é definido localmente no script de anonimização e nunca versionado.

**`titular_type` → classificação PF/PJ extraída antes do hash**
Após o hash de `titular_code`, é impossível distinguir CPF de CNPJ pelo
valor resultante. Por isso, o script extrai e persiste o tipo do documento
(`'PF'` para CPF, `'PJ'` para CNPJ) como coluna separada **antes** de
aplicar o hash. Esse campo não permite reidentificação — saber que um
titular é pessoa jurídica sem conhecer o CNPJ não expõe dados sensíveis
— mas agrega valor analítico relevante para `dim_titular` (ADR-005).

**`contract_code` → SHA-256 com salt + truncagem**
O código do contrato não identifica pessoas diretamente, mas combinado com
dados externos poderia permitir reidentificação cruzada. O hash com salt
preserva a unicidade e a capacidade de join entre `payments` e `receivables`
sem expor o identificador original. Truncado em 8 chars por ser um campo
mais curto e menos crítico que `titular_code`.

**`estate_code`, `estate_name`, `estate_address` → mapeamento determinístico**
Os três campos descrevem o mesmo objeto (empreendimento) e devem ser
substituídos de forma coerente entre si — o código fictício `1` deve
corresponder sempre ao nome fictício `"Residencial Aurora"` e ao seu
endereço fictício, independentemente de qual arquivo está sendo processado.
O script mantém um dicionário de mapeamento `real → fictício` que é
construído progressivamente à medida que novos valores únicos são encontrados
nos arquivos, garantindo consistência entre todos os 12 meses e suportando
múltiplos empreendimentos.

### Script de anonimização

O script `scripts/anonymize_and_load.py` é executado manualmente pelo
desenvolvedor para processar os dados originais. Ele:

1. Lê cada arquivo XLSX de `/data/original/YYYY-MM/`
2. Aplica as transformações definidas neste ADR campo a campo,
   em memória
3. Salva cópia Parquet anonimizada em `/data/processed/YYYY-MM/`
   para auditoria local
4. Carrega os dados diretamente no BigQuery via API
   (`raw.raw_payments` e `raw.raw_receivables`)
5. Registra a execução em `raw.pipeline_runs` (ADR-007)
6. Nunca modifica os arquivos originais
7. Nunca persiste dados anonimizados em formato intermediário
   no disco antes do carregamento

O script **não é versionado no repositório** — ele contém o salt e o
mapeamento de substituição dos dados comerciais sensíveis. O desenvolvedor
deve mantê-lo localmente junto com `/data/original/`.

O repositório contém apenas `scripts/anonymize_and_load_template.py`
com a estrutura do script e comentários explicando onde o salt e o
mapeamento devem ser preenchidos — sem os valores reais.

### Verificação pós-anonimização

O script `scripts/verify_anonymization.py` pode ser executado para
validar os dados carregados no BigQuery ou os Parquets em
`/data/processed/`:

```bash
python scripts/verify_anonymization.py
```

Este script verifica que nenhum registro contém:
- Strings que correspondam ao padrão de CPF (`\d{3}\.\d{3}\.\d{3}-\d{2}`)
- Strings que correspondam ao padrão de CNPJ (`\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}`)
- O nome real do empreendimento
- O endereço real do empreendimento

Se qualquer verificação falhar, o script encerra com erro.

---

## Motivação

- **LGPD:** dados de pessoas físicas identificáveis não podem ser expostos
  publicamente sem consentimento — a anonimização cumpre essa obrigação
- **Confidencialidade contratual:** o acordo com a incorporadora impede
  a divulgação de dados comerciais do empreendimento
- **Portfólio público:** o repositório é aberto no GitHub, aumentando
  a superfície de exposição e exigindo rigor maior do que em projetos
  internos
- **Consistência entre arquivos:** técnicas baseadas em seed fixo (Faker)
  e salt fixo (SHA-256) garantem que o mesmo valor original sempre produza
  o mesmo valor anonimizado — preservando a integridade referencial entre
  os 12 arquivos mensais e entre as abas `payments` e `receivables`
- **Legibilidade do portfólio:** substituição por valores fictícios
  semanticamente válidos (nomes, endereços) é preferível a hashes
  ilegíveis para campos que serão exibidos em dashboards e documentação

---

## Alternativas consideradas

| Alternativa | Por que foi descartada |
|---|---|
| Hash SHA-256 para todos os campos | Produziria dados ilegíveis em campos como `titular_name` e `estate_name`, prejudicando a apresentação do portfólio sem ganho de segurança adicional para este contexto |
| Dados sintéticos gerados do zero | Eliminaria todo o risco de privacidade, mas removeria a autenticidade dos padrões financeiros e temporais que valorizam o portfólio como demonstração técnica |
| Mascaramento parcial (ex: `Fernando S. T. ***`) | Reversível por engenharia social; não cumpre a obrigação de anonimização da LGPD para dados públicos |
| Exclusão dos campos sensíveis | Quebraria a estrutura do schema e removeria dimensões analíticas relevantes (ex: sem `titular_code`, não é possível fazer joins entre abas) |
| Differential privacy | Técnica válida para dados agregados publicados; excessiva e computacionalmente desnecessária para um portfólio com este volume e finalidade |
| Anonimização dentro do dbt (na camada staging) | Os arquivos XLSX entrariam no repositório com dados reais — viola o princípio estabelecido no ADR-001 de que apenas dados já anonimizados entram no Git |

---

## Consequências

### Positivas

- Nenhum dado real de pessoa física ou da incorporadora é exposto
  publicamente em nenhuma forma
- A consistência referencial do dataset é preservada — joins entre
  abas e entre arquivos mensais funcionam corretamente após anonimização
- O portfólio permanece analiticamente rico: padrões financeiros,
  temporais e de inadimplência são preservados
- O script de verificação cria uma barreira técnica contra commits
  acidentais de dados não anonimizados

### Negativas / Trade-offs

- **Script não versionado:** o `anonymize_and_load.py` completo (com salt e
  mapeamento) fica apenas na máquina do desenvolvedor — se perdido,
  a reprodução exata da anonimização é impossível; o template versionado
  permite recriar o script, mas não garante os mesmos valores de saída
- **Mapeamento de empreendimentos deve ser preservado localmente:** o
  dicionário `real → fictício` de `estate_code`, `estate_name` e
  `estate_address` é construído progressivamente — se perdido, novos
  arquivos podem gerar mapeamentos inconsistentes com os já versionados
- **Faker com seed fixo:** garante consistência, mas um atacante com
  acesso ao seed poderia mapear nomes fictícios de volta aos originais
  se tiver a lista original — risco irrelevante para portfólio público
  sem adversários conhecidos
- **Irreversibilidade dos hashes:** uma vez perdido o salt, não é
  possível recuperar CPF, CNPJ ou `contract_code` originais a partir
  dos hashes — isso é intencional, mas deve ser documentado como
  limitação operacional

### Implicações de privacidade

- A técnica adotada para `titular_name` e `titular_code` configura
  **anonimização** no sentido da LGPD — o dado resultante não permite,
  por meios razoáveis, a reidentificação do titular
- O desenvolvedor é o único controlador dos dados originais e deve
  garantir que `/data/original/` nunca seja sincronizado com nuvem
  pública (Google Drive, Dropbox, etc.) sem criptografia adicional
- Caso o projeto seja expandido para incluir dados de outras
  incorporadoras ou titulares, este ADR deve ser revisado e o script
  de anonimização atualizado antes de qualquer novo commit

---

## Decisões relacionadas

- **Depende de:** ADR-001 (Engine) — a anonimização ocorre em memória
  e o destino dos dados é o BigQuery, conforme definido no ADR-001
- **Depende de:** ADR-002 (Ingestão) — o script usa o nome da subpasta
  `YYYY-MM/` em `/data/original/` como `date_reference`; não há
  renomeação de arquivos
- **Influencia:** ADR-004 (Camadas dbt) — a camada de staging recebe
  dados já anonimizados; nenhuma lógica de anonimização deve existir
  dentro do dbt
- **Influencia:** ADR-006 (Testes e qualidade) — o script de verificação
  pós-anonimização é um gate obrigatório antes do `dbt build`

---

## Notas para agentes Claude CLI

- **CRÍTICO:** toda anonimização ocorre **antes** do dbt, no script
  `scripts/anonymize_and_load.py`. Nunca gere lógica de mascaramento
  ou hash dentro de modelos dbt — os dados já chegam anonimizados ao staging
- Os campos `titular_name` e `titular_code` nos modelos dbt contêm
  valores fictícios/hash — nunca os trate como dados reais de pessoas
- O campo `titular_code` pode conter hash de CPF ou de CNPJ — nunca
  assuma que é exclusivamente CPF ao gerar testes ou documentação
- O campo `titular_type` (`'PF'` ou `'PJ'`) é gerado pelo script de
  anonimização **antes** do hash — nunca tente derivá-lo a partir do
  `titular_code` hashado nos modelos dbt
- O campo `contract_code` contém um hash truncado — nunca tente
  revertê-lo ou compará-lo com valores originais
- Nunca gere código que faça `REVERSE()`, decode ou qualquer tentativa
  de reverter valores de `titular_code` ou `contract_code`
- Nunca gere testes dbt que comparem campos anonimizados com valores
  reais — use apenas testes estruturais (not_null, unique, accepted_values)
- `estate_code`, `estate_name` e `estate_address` podem ter múltiplos
  valores distintos nos dados — não assuma que são constantes
- Se o usuário pedir para exibir amostras de dados em documentação
  ou README, use apenas os valores já anonimizados — nunca valores
  de `/data/original/`
- Se o usuário pedir para adicionar novos campos sensíveis ao pipeline,
  oriente a atualizar este ADR e o script `anonymize_and_load.py`
  antes de qualquer execução
