local rspamd_logger = require 'rspamd_logger'
local rspamd_http = require "rspamd_http"
local rspamd_lua_utils = require "lua_util"
local ucl = require "ucl"

if confighelp then
  return
end
local rows = {}
local nrows = 0
local json_mappings
local settings = {
  limit = 10,
  index_pattern = 'rspamd-%Y.%m.%d',
  server = 'localhost:9200',
  mapping_file = '/etc/rspamd/rspamd_template.json',
  debug = false,
}
local current_index
local function read_file(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read "*a"
    file:close()
    return content
end
local function create_index(task,name)
  local function http_index_create_callback(err, code, body, headers)
    -- todo error handling disable the module maybe ? or run periodic task to retry index creation
    if settings['debug'] then
      rspamd_logger.infox(task, "After create index %1",body)
    end
  end
  rspamd_http.request({
    url = 'http://'..settings['server']..'/'..name,
    task = task,
    body = json_mappings,
    method = 'put',
    callback = http_index_create_callback
  })
end
local function elastic_send_data(task)
  local function http_index_exist_callback(err, code, body, headers)
    if code ~= 200 or err_message then
      create_index(task,current_index)
    end
  end
  local es_index = os.date(settings['index_pattern'])
  if es_index ~= current_index then
    create_index(task,es_index)
    current_index = es_index
  end
  rspamd_http.request({
    url = 'http://'..settings['server']..'/'..current_index,
    task = task,
    method = 'head',
    callback = http_index_exist_callback
  })
  local bulk_json = ""
  for key,value in pairs(rows) do
    bulk_json= bulk_json..'{ "index" : { "_index" : "'..es_index..'", "_type" : "logs" ,"pipeline": "rspamd-geoip"} }'.."\n"
    bulk_json= bulk_json..ucl.to_format(value, 'json-compact').."\n"
  end
  local function http_index_data_callback(err, code, body, headers)
    -- todo error handling we may store the rows it into redis and send it again later
    if settings['debug'] then
      rspamd_logger.infox(task, "After create data %1",body)
    end
  end
  rspamd_http.request({
    url = 'http://'..settings['server']..'/'..es_index..'/_bulk',
    headers = {
      ['Content-Type'] = 'application/x-ndjson',
    },
    body = bulk_json,
    task = task,
    method = 'post',
    callback = http_index_data_callback
  })

end
local function get_general_metadata(task)
  local r = {}
  local ip_addr = task:get_ip()
  r.ip = tostring(ip_addr) or 'unknown'
  r.webmail = false
  if ip_addr  then
    r.is_local = ip_addr:is_local()
    local origin = task:get_header('X-Originating-IP')
    if origin then
        r.webmail = true
        r.ip = origin
    end
  end
  r.user = task:get_user() or 'unknown'
  r.qid = task:get_queue_id() or 'unknown'
  r.action = task:get_metric_action('default')

  local s = task:get_metric_score('default')[1]
  r.score =  s

  local rcpt = task:get_recipients('smtp')
  if rcpt then
    local l = {}
    for _, a in ipairs(rcpt) do
      table.insert(l, a['addr'])
    end
      r.rcpt = l
  else
    r.rcpt = 'unknown'
  end
  local from = task:get_from('smtp')
  if ((from or E)[1] or E).addr then
    r.from = from[1].addr
  else
    r.from = 'unknown'
  end
  local syminf = task:get_symbols_all()
  r.symbols = syminf
  r.asn = {}
  local pool = task:get_mempool()
  r.asn.country = pool:get_variable("country") or 'unknown'
  r.asn.asn   = pool:get_variable("asn") or 0
  r.asn.ipnet = pool:get_variable("ipnet") or 'unknown'
  local function process_header(name)
    local hdr = task:get_header_full(name)
    if hdr then
      local l = {}
      for _, h in ipairs(hdr) do
        table.insert(l, h.decoded)
      end
      return l
    else
      return 'unknown'
    end
  end
  r.header_from = process_header('from')
  r.header_to = process_header('to')
  r.header_subject = process_header('subject')
  r.header_date = process_header('date')
  r.message_id = task:get_message_id()
  return r
end

local function elastic_collect(task)
  if rspamd_lua_utils.is_rspamc_or_controller(task) then return end
  local row = {['rspam_meta'] = get_general_metadata(task), ['@timestamp'] = os.date('%Y-%m-%dT%H:%M:%SZ')}
  table.insert(rows, row)
  nrows = nrows + 1
  if nrows > settings['limit'] then
    elastic_send_data(task)
    nrows = 0
    rows = {}
  end
end
local opts = rspamd_config:get_all_opt('elastic')
local enabled = true;
if opts then
    for k,v in pairs(opts) do
      settings[k] = v
    end
    if not settings['server'] then
      rspamd_logger.infox(rspamd_config, 'no elastic servers are specified, disabling module')
      enabled = false
    end
    if not settings['mapping_file'] then
        rspamd_logger.infox(rspamd_config, 'elastic mapping_file is required, disabling module')
        enabled = false
    end
end
json_mappings = read_file(settings['mapping_file']);
if not json_mappings then
      rspamd_logger.infox(rspamd_config, 'elastic unable to read mappings, disabling module')
      enabled = false
end
if enabled == true then
  rspamd_logger.infox(rspamd_config, 'starting elastic module')
  current_index = os.date(settings['index_pattern'])
  rspamd_config:register_symbol({
    name = 'ELASTIC_COLLECT',
    type = 'postfilter',
    callback = elastic_collect,
    priority = 10
  })
end
