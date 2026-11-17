import { AreaTexto, Campo, Escolha } from "@/components/formulario";
import { listarAutores, listarCategorias, listarEditoras } from "@/lib/acervo";
import type { LivroDetalhe } from "@/lib/catalogo";

export async function CamposLivro({ livro }: { livro?: LivroDetalhe }) {
  const [autores, editoras, categorias] = await Promise.all([listarAutores(), listarEditoras(), listarCategorias()]);
  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
      <Campo nome="titulo" rotulo="Título" padrao={livro?.titulo} required className="sm:col-span-2" />
      <Campo nome="isbn" rotulo="ISBN" padrao={livro?.isbn} />
      <Campo nome="ano" rotulo="Ano" type="number" padrao={livro?.ano} />
      <Escolha nome="categoriaId" rotulo="Categoria" padrao={livro?.categoria.id} opcoes={categorias.map((c) => ({ valor: c.id, rotulo: c.nome }))} />
      <Escolha nome="editoraId" rotulo="Editora" padrao={livro?.editoraId} opcoes={editoras.map((e) => ({ valor: e.id, rotulo: e.nome }))} />
      <Escolha nome="autores" rotulo="Autores (Ctrl para vários)" multipla padrao={livro?.autores.map((a) => a.id)} opcoes={autores.map((a) => ({ valor: a.id, rotulo: a.nome }))} className="sm:col-span-2" />
      <Campo nome="capaUrl" rotulo="URL da capa" padrao={livro?.capaUrl} className="sm:col-span-2" />
      <AreaTexto nome="sinopse" rotulo="Sinopse" padrao={livro?.sinopse} className="sm:col-span-2" />
    </div>
  );
}
