
    const municipiosPorProvincia = {
        luanda: [
            'Belas', 'Cacuaco', 'Cazenga', 'Ícolo e Bengo', 'Luanda', 'Quilamba Quiaxi', 'Talatona', 'Viana'
        ],
        benguela: [
            'Baía Farta', 'Balombo', 'Benguela', 'Bocoio', 'Caimbambo', 'Catumbela', 'Chongoroi', 'Cubal', 'Ganda', 'Lobito'
        ],
        huambo: [
            'Bailundo', 'Catchiungo', 'Caála', 'Ecunha', 'Huambo', 'Londuimbali', 'Longonjo', 'Mungo', 'Tchicala-Tcholoanga', 'Tchindjenje', 'Ucuma'
        ]
    };
    const provinciaSelect = document.getElementById('provincia');
    const municipioField = document.getElementById('municipio-field');
    const municipioSelect = document.getElementById('municipio');

    provinciaSelect.addEventListener('change', function() {
        const provincia = this.value;
        municipioSelect.innerHTML = '<option value="" hidden>Selecione o município</option>';
        if (municipiosPorProvincia[provincia]) {
            municipiosPorProvincia[provincia].forEach(function(mun) {
                const opt = document.createElement('option');
                opt.value = mun.toLowerCase().replace(/ /g, '_');
                opt.textContent = mun;
                municipioSelect.appendChild(opt);
            });
            municipioField.style.display = 'block';
            municipioSelect.required = true;
        } else {
            municipioField.style.display = 'none';
            municipioSelect.required = false;
        }
    });

    //==========TRANSIÇÃO LOGIN/CADASTRO==========
    function optin_move() {
        document.getElementById('login').classList.toggle('login_move')
     document.getElementById('logup').classList.toggle('cadastro_move')
    }