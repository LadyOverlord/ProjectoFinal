document.addEventListener("DOMContentLoaded", () => {
  menu();
});

function menu() {
  const itens = document.querySelectorAll(".item");
  const tabs = document.querySelectorAll(".tab");

  itens.forEach(btn => {
    btn.addEventListener("click", () => {

      itens.forEach(b => b.classList.remove("ativo"));
      tabs.forEach(t => t.classList.remove("ativo"));

      btn.classList.add("ativo");

      const id = btn.getAttribute("data-tab");
      document.getElementById(id).classList.add("ativo");
    });
  });
}