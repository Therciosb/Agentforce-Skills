import { createElement } from 'lwc';
import SkillDependencyTree from 'c/skillDependencyTree';
import getTree from '@salesforce/apex/Agent_Skill_DependencyProvider.getTree';

// Require the adapter lazily inside the factory: jest hoists jest.mock() above
// imports, so referencing an out-of-scope binding here is disallowed.
jest.mock(
    '@salesforce/apex/Agent_Skill_DependencyProvider.getTree',
    () => {
        const {
            createApexTestWireAdapter
        } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

describe('c-skill-dependency-tree', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    function flush() {
        return Promise.resolve();
    }

    it('maps nested tree data into lightning-tree items (root + children)', async () => {
        const el = createElement('c-skill-dependency-tree', {
            is: SkillDependencyTree
        });
        el.recordId = 'a00000000000001';
        document.body.appendChild(el);

        getTree.emit({
            name: 'skill-x',
            label: 'skill-x',
            type: 'Skill',
            status: 'active',
            seen: false,
            children: [
                {
                    name: 'workflow-y',
                    label: 'workflow-y',
                    type: 'Workflow',
                    status: 'active',
                    seen: false,
                    children: []
                }
            ]
        });
        await flush();

        const tree = el.shadowRoot.querySelector('lightning-tree');
        expect(tree).not.toBeNull();
        expect(tree.items).toHaveLength(1);
        expect(tree.items[0].name).toBe('skill-x');
        expect(tree.items[0].items).toHaveLength(1);
        expect(tree.items[0].items[0].name).toBe('workflow-y');
    });

    it('flags missing/inactive nodes and "already shown" (seen) nodes in metatext', async () => {
        const el = createElement('c-skill-dependency-tree', {
            is: SkillDependencyTree
        });
        el.recordId = 'a00000000000001';
        document.body.appendChild(el);

        getTree.emit({
            name: 'skill-root',
            label: 'skill-root',
            type: 'Skill',
            status: 'active',
            seen: false,
            children: [
                {
                    name: 'skill-missing',
                    label: 'skill-missing',
                    type: 'Skill',
                    status: 'missing',
                    seen: false,
                    children: []
                },
                {
                    name: 'skill-dup',
                    label: 'skill-dup',
                    type: 'Skill',
                    status: 'active',
                    seen: true,
                    children: []
                }
            ]
        });
        await flush();

        const tree = el.shadowRoot.querySelector('lightning-tree');
        expect(tree.items[0].items[0].metatext).toContain('missing');
        expect(tree.items[0].items[1].metatext).toContain('already shown');
    });

    it('renders an error message when the wire returns an error', async () => {
        const el = createElement('c-skill-dependency-tree', {
            is: SkillDependencyTree
        });
        el.recordId = 'a00000000000001';
        document.body.appendChild(el);

        getTree.error();
        await flush();

        const tree = el.shadowRoot.querySelector('lightning-tree');
        expect(tree).toBeNull();
        const errDiv = el.shadowRoot.querySelector('.slds-text-color_error');
        expect(errDiv).not.toBeNull();
        // The wire adapter reshapes the error body in jsdom, so we assert the
        // core contract (error branch renders a non-empty message) rather than
        // an exact string.
        expect(errDiv.textContent.length).toBeGreaterThan(0);
    });
});
