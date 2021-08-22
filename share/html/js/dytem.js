class Repeated {
  constructor(id, placeholder) {
    this.id = id;
    this.placeholder = placeholder;
    this.template = $(document.getElementById(this.id));
    this.elements = [];
  }

  append() {
    const lastElement = (this.elements.length > 0)
      ? this.elements[this.elements.length - 1]
      : this.placeholder;
    const elementToAppend = this.template.clone();
    elementToAppend.removeAttr('id');
    window.Dytem.addChildrenField(elementToAppend, `${this.id}.`, elementToAppend);
    elementToAppend.show();
    lastElement.after(elementToAppend);
    this.elements.push(elementToAppend);
    return elementToAppend;
  }

  at(idx) {
    return this.elements[idx];
  }

  size() {
    return this.elements.length;
  }

  resize(n) {
    if (n < this.elements.length) {
      const ref = this.elements.slice(n);
      for (let i = 0; i < ref.length; i += 1) {
        ref[i].remove();
      }
      return ([].splice.apply(this.elements, [n, 9e9].concat([])), []);
    }
    if (n > this.elements.length) {
      const results = [];
      const ref3 = this.elements.length;
      for (let i = ref3; ref3 <= n ? i < n : i > n; i += ref3 <= n ? 1 : -1) {
        results.push(this.append());
      }
      return results;
    }
  }

  clear() {
    for (let i = 0; i < this.elements.length; i += 1) {
      this.elements[i].remove();
    }
    this.elements = [];
    return this.elements;
  }
}

window.Dytem = {
  init() {
    window.Dytem.addChildrenField($('body'), null, window.Dytem);
  },
  assign(obj, element) {
    element || (element = window.Dytem);
    if (typeof obj === 'string') {
      return element.text(obj);
    }
    if (obj instanceof Array) {
      element.clear();
      const results = [];
      for (let i = 0; i < obj.length; i += 1) {
        results.push(window.Dytem.assign(obj[i], element.append()));
      }
      return results;
    }
    const results2 = [];
    Object.keys(obj).forEach((name) => {
      if (name === 'text') {
        results2.push(element.text(obj[name]));
      } else if (name === 'html') {
        results2.push(element.html(obj[name]));
      } else if (element[name]) {
        results2.push(window.Dytem.assign(obj[name], element[name]));
      } else if (element.attr) {
        results2.push(element.attr(name, obj[name]));
      } else {
        throw Error(`unknown field: ${name}`);
      }
    });
    return results2;
  },
  addChildrenField(element, prefix, target) {
    element.find('[id]').each((i, child) => {
      const childId = $(child).attr('id');
      if (prefix) $(child).removeAttr('id');
      const escPrefix = prefix ? prefix.replace(/\./, '\\.') : '';
      if (childId.match(new RegExp(`^${escPrefix}([^\\.]+)$`))) {
        const name = RegExp.$1;
        target[name] = ($(child).hasClass('repeated'))
          ? new Repeated(childId, $(child))
          : $(child);
      }
    });
  },
};
