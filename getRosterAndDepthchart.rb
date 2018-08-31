require 'nokogiri'
require 'open-uri'
require 'json'
require 'csv'
require 'pp'

ENV['SSL_CERT_FILE'] = File.join(File.dirname($0), 'cert.pem')

pp 'start getRosterAndDepthchart ...'

useCache = false
useLog = false

def log(s)
    return unless useLog
    File.open('log.log', 'a+b') do |f|
        f.puts s
    end
end
DECODE_TABLE = {
    '&#233;' => 'é',
    '&#241;' => 'ñ',
    '&#231;' => 'ç',
}
def decode(str)
    str.gsub(/&#.+;/, DECODE_TABLE)
end

File.open('log.log', 'wb') if useLog

roster_url = [
    {conf: 'afc', url: 'https://en.wikipedia.org/wiki/List_of_current_AFC_team_rosters'},
    {conf: 'nfc', url: 'https://en.wikipedia.org/wiki/List_of_current_NFC_team_rosters'}
]
teamsName = {
    'Buffalo Bills'        => 'BUF',
    'Miami Dolphins'       => 'MIA',
    'New England Patriots' => 'NE',
    'New York Jets'        => 'NYJ',
    'Baltimore Ravens'     => 'BAL',
    'Cincinnati Bengals'   => 'CIN',
    'Cleveland Browns'     => 'CLE',
    'Pittsburgh Steelers'  => 'PIT',
    'Houston Texans'       => 'HOU',
    'Indianapolis Colts'   => 'IND',
    'Jacksonville Jaguars' => 'JAC',
    'Tennessee Titans'     => 'TEN',
    'Denver Broncos'       => 'DEN',
    'Kansas City Chiefs'   => 'KC',
    'Los Angeles Chargers' => 'LAC',
    'Oakland Raiders'      => 'OAK',
    'Dallas Cowboys'       => 'DAL',
    'New York Giants'      => 'NYG',
    'Philadelphia Eagles'  => 'PHI',
    'Washington Redskins'  => 'WAS',
    'Chicago Bears'        => 'CHI',
    'Detroit Lions'        => 'DET',
    'Green Bay Packers'    => 'GB',
    'Minnesota Vikings'    => 'MIN',
    'Atlanta Falcons'      => 'ATL',
    'Carolina Panthers'    => 'CAR',
    'New Orleans Saints'   => 'NO',
    'Tampa Bay Buccaneers' => 'TB',
    'Arizona Cardinals'    => 'ARI',
    'Los Angeles Rams'     => 'LAR',
    'San Francisco 49ers'  => 'SF',
    'Seattle Seahawks'     => 'SEA',
}
position = {
    'Quarterbacks' => 'QB',
    'Running backs' => 'RB',
    'Wide receivers' => 'WR',
    'Tight ends' => 'TE',
    'Offensive linemen' => 'OL',
    'Defensive linemen' => 'DL',
    'Linebackers' => 'LB',
    'Defensive backs' => 'DB',
    'Special teams' => 'SP',
    'Reserve lists' => 'R',
}

data_dir = 'data'
charset = nil
data = []
depthChartUrl = []
Dir.mkdir(data_dir) unless Dir.exists?(data_dir)
# fetch roster
roster_url.each do |ru|
    html = ''
    charset = 'UTF8'
    if useCache
        html = File.read(ru[:conf] + '.html')
    else
        html = open(ru[:url]) do |f|
            charset = f.charset
            f.read
        end
        File.write(data_dir + '/' + ru[:conf] + '.html', html)
    end
    doc = Nokogiri::HTML.parse(html, nil, charset)
    doc.search('.toccolours').each do |node|
        data << node.inner_text.split(/\n/)
        team = teamsName[node.search('div')[0].inner_text.gsub(/\s\S+$/, '')]
        url = (node.search('a').find {|n| n.inner_text == 'Depth chart'})['href']
        depthChartUrl << {team: team, url: url}
    end
end
# parse roster (prepare)
teamsNameSplit = teamsName.keys.map{|t| t + ' rosterviewtalkedit'}
d2 = []
data.each do |team|
    team.each do |d|
        next if d == ''
        break if d == 'Rookies in italics'
        if teamsNameSplit.include?(d)
            d2 << d
            next
        end
        d2 << d
    end
end
# parse roster
roster = []
team = ''
pos = ''
d2.each do |d|
    if teamsNameSplit.include?(d)
        team = teamsName[d.gsub(/\s\S+$/, '')]
        next
    end
    if position.has_key?(d)
        pos = position[d]
        next
    end
    if d =~ /\d+\s.+/ || d =~ /--\s.+/
        # IRなど特記事項
        if notice = d.match(/\((.+)\)/)
            notice = notice[1]
            d.gsub!(/\s+\((.+)\)\s*/, '')
        else
            notice = ''
        end
        # 詳細ポジション
        if p = d.match(/([A-Z\/]+)$/)
            # RG3対策
            if p[1] != 'II' && p[1] != 'III' && p[1] != 'IV' && p[1] != 'V'
                pos2 = p[1]
                d.gsub!(/\s+[A-Z\/]+$/, '')
            else
                pos2 = pos
            end
        else
            pos2 = pos
        end
        # 背番号、名前
        if ms = d.match(/^(..)\s(.+)$/)
            num = '-' if ms[1] == '--'
            if n = ms[1].match(/\D(\d)/)
                num = n[1]
            else
                num = ms[1]
            end
            name = ms[2]
        else
            if ms = d.match(/^(.)\s(.+)$/)
                num = ms[1]
                name = ms[2]
            else
                num = -1
                name = d
            end
        end
        roster << {team: team, num: num, name: name, position1: pos, position2: pos2, notice: notice}
    end
end
# write roster
=begin
CSV.open(data_dir + '/' + 'roster.csv', 'wb') do |f|
    roster.each do |d|
        next if d == []
        f << [d[:team], d[:position1], d[:position2], d[:name], d[:num], d[:notice]]
    end
end
=end

# fetch depth chart from team site
unless useCache
    Dir.mkdir(data_dir + '/' + 'depth_chart_html') unless Dir.exist?(data_dir + '/' + 'depth_chart_html')
    depthChartUrl.each do |dc|
        pp 'loading ' + dc[:team]
        begin
            html = open(dc[:url], 'r:utf-8') do |f|
                File.open(data_dir + '/' + 'depth_chart_html/' + dc[:team] + '.html', 'wb:utf-8') do |f1|
                    f1.puts f.read.gsub(/<title>.+<\/title>/, '').gsub(/<meta.+>/, '') # NYG, SF対策
                end
            end
            dc[:hasDepthChart] = true
        rescue => err
            pp err
            File.open(data_dir + '/' + 'depth_chart_html/' + dc[:team] + '.html', 'wb')
            dc[:hasDepthChart] = false
        end
    end
else
    pp 'skip fetch depth-chart'
end
depthChartData = []
# parse chart
depthChartUrl.each do |dc|
    pp 'make ' + dc[:team]
    html = File.read(data_dir + '/' + 'depth_chart_html/' + dc[:team] + '.html')
    next if html == ''
    td = []
    doc = Nokogiri::HTML.parse(html, 'UTF-8')
    tables = doc.search('.nfl-t-depth-chart__table')
    td = tables.search('td').map{|x| x.inner_html.strip}.select{|x| x.strip != ''}
    pos = ''
    rank = 1
    td.each do |x|
        if x =~ /^[A-Z]+$/
            pos = x
            rank = 1
            next
        end
        if  x.kind_of?(String) && x != ''
            rgs = x.scan(/<a.+?>(.+)<\/a>/)
            rgs.each do |name|
                name0 = name[0].gsub(/&#160;/, '')
                if name0.match(/&#/)
                    name0 = decode(name0)
                end
                depthChartData << {team: dc[:team], pos: pos, rank: rank, name: name0}
            end
            rank += 1
        end
    end
end
# write depth chart
=begin
CSV.open(data_dir + '/' + 'depthchart.csv', 'wb') do |f|
    depthChartData.each do |d|
        next if d == []
        f << [d[:team], d[:pos], d[:rank], d[:name]]
    end
end
=end
# merge roster and chart
roster.each do |r|
    d = depthChartData.select{|x| x[:team] + x[:name].gsub(/\s/, '') == r[:team] + r[:name].gsub(/\s/, '')}[0]
    if d
        r[:rank] = d[:rank]
    else
        r[:rank] = '-'
    end
end
CSV.open('rosterAndChart.csv', 'wb') do |f|
    f << ['team', 'position', 'position_ex', 'name', 'number', 'depth_rank', 'notice']
    roster.each do |d|
        next if d == []
        f << [d[:team], d[:position1], d[:position2], d[:name], d[:num], d[:rank], d[:notice]]
    end
end
