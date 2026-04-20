document.addEventListener("DOMContentLoaded", function () {
  iniciarMenu();
  iniciarAbas();
});

function iniciarMenu() {
  const itens = document.querySelectorAll(".item");
  const tabs = document.querySelectorAll(".tab");

  itens.forEach(function (item) {
    item.addEventListener("click", function () {
      const alvo = item.getAttribute("data-tab");

      if (!alvo) return;

      itens.forEach(function (btn) {
        btn.classList.remove("ativo");
      });

      tabs.forEach(function (tab) {
        tab.classList.remove("ativo");
      });

      item.classList.add("ativo");

      const secao = document.getElementById(alvo);
      if (secao) {
        secao.classList.add("ativo");
      }
    });
  });
}

function iniciarAbas() {
  const abas = document.querySelectorAll(".aba");
  const tabs = document.querySelectorAll(".tab");

  abas.forEach(function (aba) {
    aba.addEventListener("click", function () {
      const alvo = aba.getAttribute("data-tab");

      if (!alvo) return;

      abas.forEach(function (btn) {
        btn.classList.remove("ativa");
      });

      tabs.forEach(function (tab) {
        tab.classList.remove("ativo");
      });

      aba.classList.add("ativa");

      const secao = document.getElementById(alvo);
      if (secao) {
        secao.classList.add("ativo");
      }

      const itemMenu = document.querySelector('.item[data-tab="' + alvo + '"]');
      if (itemMenu) {
        document.querySelectorAll(".item").forEach(function (btn) {
          btn.classList.remove("ativo");
        });
        itemMenu.classList.add("ativo");
      }
    });
  });
}