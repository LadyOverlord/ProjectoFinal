 // Abrir modal
        document.getElementById('relatar').addEventListener('click', function() {
            document.getElementById('modal-relatar').style.display = 'flex';
        });
        // Fechar modal
        document.getElementById('fechar-modal-relatar').addEventListener('click', function() {
            document.getElementById('modal-relatar').style.display = 'none';
        });
        // Fechar ao clicar fora do modal
        document.getElementById('modal-relatar').addEventListener('click', function(e) {
            if (e.target === this) this.style.display = 'none';
        });
        // (Próximos passos: lidar com envio do formulário e integração Firebase)