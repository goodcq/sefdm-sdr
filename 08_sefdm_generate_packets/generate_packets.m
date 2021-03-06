%%
% Генерирует файл, содержащий baseband signal, который будем передавать
% Сигнал представляет пакет или последовательность пакетов
% О структуре файла/пакета см. packets/readme.txt
%
% Packet:
%   1) |802.11a prmbl|
%   2) |OFDM-символы для channel estimation (заголовок)|
%   3) |OFDM-символ, содержащий порядковый номер пакета|
%   4) |Полезная нагрузка из SEFDM-символов|
%
% 1), 2) и 4) - одинаковые для всех пакетов в файле!
%

%%
% Параметры генерируемого файла
clear;
path(path, './functions/');
path(path, '../02_ofdm_phy_802_11a_model/ofdm_phy_802_11a/');

save_IQ = false; % Сохранять в файл сгенерированный сигнал или нет

add_noise = true; % Добавить ли в сигнал АБГШ
SNR = 12; % ОСШ, дБ

add_start_end_zeros = true; % Добавить ли в начало и конец файла нулевые отсчёты
n_start_end_zeros = 10e4; % Кол-во нулей в начале и в конце файла

pckt_n       = 20000; % Кол-во пакетов
pckt_n_zeros = 1000; % Кол-во нулей между пакетами

hdr_n_sym  = 6; % Кол-во ofdm-символов в заголовке (для channel estimation)
hdr_len_cp = 6; % Длина CP у ofdm-символов

pld_n_sym  = 20; % Кол-во sefdm-символов в полезной нагрузке
pld_len_cp = 6; % Длина CP у sefdm-символов

sym_ifft_size    = 28; % IFFT size (также соответсвует длине ofdm-символов в заголовке)
sym_len          = 26; % длина sefdm-символа
sym_n_inf        = 20; % кол-во поднесущих с информацией
sym_len_left_gi  = 3; % длина левого GI по частоте
sym_len_right_gi = 2; % длина правого GI по частоте
sym_modulation   = 'bpsk'; % 'bpsk' or 'qpsk' 

filename_bits = './bits/information_bits.mat'; % variable "bit"

alfa = sym_len / sym_ifft_size;
if strcmp(sym_modulation, 'bpsk')
	modulation = 1;
elseif strcmp(sym_modulation, 'qpsk')
	modulation = 2;
else
	error('Bad @sym_modulation');
end

sefdm_init(sym_ifft_size, alfa, sym_len_right_gi, sym_len_left_gi, modulation);

%%
% Формирование полезной нагрузки пакета
load(filename_bits);
n_bit_in_pld = modulation * sym_n_inf * pld_n_sym;
tx_bit = bit(1 : n_bit_in_pld);
tx_bit = reshape(tx_bit, modulation * sym_n_inf, pld_n_sym);
clear bit;

tx_modulation_sym = ConstellationMap(tx_bit, modulation); % Modulation Mapping

tx_sefdm_sym = sefdm_IFFT( sefdm_allocate_subcarriers(tx_modulation_sym, 'tx'), ...
                           'sefdm' ); % Generate SEFDM-symbols

tx_cp_sefdm_sym = sefdm_add_cp(tx_sefdm_sym, pld_len_cp); % Add CP

payload = reshape(tx_cp_sefdm_sym, 1, (sym_len + pld_len_cp) * pld_n_sym); % Payload

%%
% Формирование 802.11a преамбулы
short_training_symbols = GenerateSTS('Rx');
long_training_symbols  = GenerateLTS('Rx');
prmbl = [short_training_symbols, long_training_symbols];

%%
% Формирование заголовка (ofdm-символы для channel estimation)
pilot_modulation = 1; % BPSK
load(filename_bits);
n_bit_in_hdr = pilot_modulation * sym_n_inf * hdr_n_sym;
pilot_bit = bit(1 : n_bit_in_hdr);
pilot_bit = reshape(pilot_bit, pilot_modulation * sym_n_inf, hdr_n_sym);
clear bit;

pilot_modulation_sym = ConstellationMap(pilot_bit, pilot_modulation); % Modulation Mapping

pilot_ofdm_sym = sefdm_IFFT( sefdm_allocate_subcarriers(pilot_modulation_sym, 'tx'), ...
                             'ofdm' ); % Generate OFDM-symbols

pilot_cp_ofdm_sym = sefdm_add_cp(pilot_ofdm_sym, hdr_len_cp); % Add CP

header = reshape(pilot_cp_ofdm_sym, 1, (sym_ifft_size + hdr_len_cp) * hdr_n_sym); % Header

%%
% Формирование OFDM-символа, содержащего порядковый номер пакета
no_bit = de2bi(1 : pckt_n, sym_n_inf, 'left-msb').';
no_modulation_sym = ConstellationMap(no_bit, 1); % Modulation Mapping
no_ofdm_sym = sefdm_IFFT( sefdm_allocate_subcarriers(no_modulation_sym, 'tx'), ...
                          'ofdm' ); % Generate OFDM-symbol
pckt_no = sefdm_add_cp(no_ofdm_sym, hdr_len_cp).'; % Add CP

%%
% Оценка cпектральной плотности шума
% ( == средней мощности шума, т.к. Pn = No * W (или No/2),
%   W = Fd по-хорошему, но у нас оцифровки и Fd = 1 (в цифре полоса 1, а половина полосы 1/2) ) ?
pckt = [prmbl, header, payload];
pckt_len = length(pckt); %length(prmbl) + length(header) + length(payload);
Ps = sum (abs(pckt).^2 ) / pckt_len;
SNR_r = 10^(SNR / 10); % в разы
Pn = Ps / SNR_r;
No = Pn;
clear pckt pckt_len SNR_r Ps Pn

%%
% Формирования файла
pckt_no_len = sym_ifft_size + hdr_len_cp; % длина OFDM-символа с порядковым номером пакета
pckt = [prmbl, header, zeros(1, pckt_no_len), payload, zeros(1, pckt_n_zeros)]; % пакет + нули в конце


% Все пакеты в виде 2d массива,
% где каждая строка - отдельный пакет
stream = repmat(pckt, pckt_n, 1);

index = length(prmbl) + length(header) + 1 : length(prmbl) + length(header) + pckt_no_len;
stream(:, index) = pckt_no; % вставили OFDM-символ, содержащий номер пакета

stream = reshape(stream.', 1, []);

%%
% Добавили нули в начале и конец потока
% (на случай, если GNU Radio будет обрезать входной/выходной файл)
add_start_end_zeros_name = [];
if add_start_end_zeros

	stream = [ zeros(1, n_start_end_zeros), stream, zeros(1, n_start_end_zeros) ];
	add_start_end_zeros_name = [add_start_end_zeros_name , ...
		'z_', num2str(n_start_end_zeros), '__'];
end

%%
% Добавили шум, если надо
add_noise_name = [];
if add_noise

	noise = sqrt(No/2) * ( randn(1, length(stream)) + 1i * randn(1, length(stream)) );
	stream = stream + noise;
% 	stream = stream + sqrt(No/2) * ( randn(1, length(stream)) + 1i * randn(1, length(stream)) );
	add_noise_name = [add_noise_name , ...
		'n_', num2str(SNR), '__'];
	clear noise
	
end

%%
% Запись файла
if save_IQ

	filename = [ 'packets/sefdm__', ...
		'pckt_', num2str(pckt_n),        '_', num2str(pckt_n_zeros), '__', ...
		'hdr_',  num2str(hdr_n_sym),     '_', num2str(hdr_len_cp),   '__', ...
		'pld_',  num2str(pld_n_sym),     '_', num2str(pld_len_cp),   '__', ...
		'sym_',  num2str(sym_ifft_size),    '_', num2str(sym_len),         '_', ...
				 num2str(sym_n_inf),        '_', num2str(sym_len_left_gi), '_', ...
				 num2str(sym_len_right_gi), '_', sym_modulation,     '__', ...
		add_start_end_zeros_name, ...
		add_noise_name, ...
		'.dat' ];

	IQ = single(zeros(1, 2 * length(stream)));
	IQ(1 : 2 : end) = single(real(stream));
	IQ(2 : 2 : end) = single(imag(stream));

	fprintf('Максимальные значения Im и Re в сгенерированном сигнале\n');
	fprintf( 'Re: %-8f %-8f\n', max(real(stream)), min(real(stream)) );
	fprintf( 'Im: %-8f %-8f\n', max(imag(stream)), min(imag(stream)));

	if exist(filename, 'file') ~= 0
		error('File is exist'); 
	end
	fd = fopen(filename, 'wb');
	if (fd == -1)
		error('File is not opened');  
	end
	fwrite(fd, IQ, 'float32');
	fclose(fd);

end



