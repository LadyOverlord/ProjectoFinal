   (function(){
      function isLoggedIn(){
        return !!(localStorage.getItem('authToken') || localStorage.getItem('userLoggedIn') === 'true');
      }
      document.addEventListener('click', function(e){
        var el = e.target.closest && e.target.closest('button, a');
        if(!el) return;
        // allow clicking login page link itself
        if((el.tagName === 'A' && /\blogin\.html\b/.test(el.getAttribute('href')||''))) return;
        if(isLoggedIn()) return;
        e.preventDefault();
        window.location.href = 'login_cadastro.html';
      }, true);
    })();

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